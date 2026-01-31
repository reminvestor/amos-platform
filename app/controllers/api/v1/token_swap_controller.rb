# frozen_string_literal: true

module Api
  module V1
    # TokenSwapController handles token swap operations via Jupiter
    #
    # Allows users to:
    # - Get quotes for AMOS → USDC/SOL/etc
    # - Execute swaps during claim process
    # - Check current AMOS prices
    class TokenSwapController < Api::V1::BaseController
      before_action :authenticate_user!, except: [:price, :supported_tokens]

      # GET /api/v1/swap/quote
      # Get a swap quote for AMOS to another token
      def quote
        output_currency = params[:output_currency]&.downcase || 'usdc'
        amount = params[:amount].to_f

        unless amount > 0
          return render json: { error: 'Amount must be positive' }, status: :unprocessable_entity
        end

        unless JupiterSwapService.supported_output_tokens.include?(output_currency.to_sym)
          return render json: { 
            error: "Unsupported currency: #{output_currency}",
            supported: JupiterSwapService.supported_output_tokens
          }, status: :unprocessable_entity
        end

        begin
          quote = case output_currency
                  when 'usdc'
                    JupiterSwapService.quote_amos_to_usdc(amount)
                  when 'sol'
                    JupiterSwapService.quote_amos_to_sol(amount)
                  else
                    JupiterSwapService.get_quote(
                      input_mint: JupiterSwapService.amos_mint,
                      output_mint: JupiterSwapService.mint_for(output_currency),
                      amount: (amount * 1_000_000_000).to_i
                    )
                  end

          render json: {
            input_currency: 'amos',
            output_currency: output_currency,
            input_amount: amount,
            output_amount: quote[:output_amount_human],
            rate: quote[:rate],
            price_impact_pct: quote[:price_impact_pct],
            expires_in_seconds: 30,  # Quotes are short-lived
            quote_id: SecureRandom.uuid  # For tracking
          }

        rescue JupiterSwapService::InsufficientLiquidityError
          render json: { 
            error: 'Insufficient liquidity for this swap amount',
            suggestion: 'Try a smaller amount or swap to AMOS directly'
          }, status: :unprocessable_entity

        rescue JupiterSwapService::QuoteError => e
          render json: { error: e.message }, status: :service_unavailable
        end
      end

      # GET /api/v1/swap/price
      # Get current AMOS price (public endpoint)
      def price
        usdc_price = JupiterSwapService.amos_price_usdc
        sol_price = JupiterSwapService.amos_price_sol

        render json: {
          token: 'AMOS',
          prices: {
            usdc: usdc_price,
            sol: sol_price
          },
          has_liquidity: JupiterSwapService.has_liquidity?,
          updated_at: Time.current
        }
      end

      # GET /api/v1/swap/supported_tokens
      # List supported output tokens (public endpoint)
      def supported_tokens
        render json: {
          input_token: {
            symbol: 'AMOS',
            mint: JupiterSwapService.amos_mint,
            decimals: 9
          },
          output_tokens: JupiterSwapService::TOKEN_MINTS.map do |symbol, mint|
            {
              symbol: symbol.to_s.upcase,
              mint: mint,
              decimals: symbol == :usdc || symbol == :usdt ? 6 : 9
            }
          end
        }
      end

      # POST /api/v1/swap/prepare
      # Prepare a swap transaction for user to sign
      def prepare
        unless current_user.solana_wallet_address.present?
          return render json: { error: 'No wallet connected' }, status: :unprocessable_entity
        end

        output_currency = params[:output_currency]&.downcase || 'usdc'
        amount = params[:amount].to_f

        begin
          # Get fresh quote
          quote = case output_currency
                  when 'usdc'
                    JupiterSwapService.quote_amos_to_usdc(amount)
                  when 'sol'
                    JupiterSwapService.quote_amos_to_sol(amount)
                  else
                    raise ArgumentError, "Unsupported: #{output_currency}"
                  end

          # Build transaction
          swap_tx = JupiterSwapService.get_swap_transaction(
            quote: quote,
            user_wallet: current_user.solana_wallet_address
          )

          render json: {
            success: true,
            swap_transaction: swap_tx[:swap_transaction],
            last_valid_block_height: swap_tx[:last_valid_block_height],
            quote: {
              input_amount: amount,
              output_amount: quote[:output_amount_human],
              rate: quote[:rate],
              price_impact_pct: quote[:price_impact_pct]
            },
            message: 'Sign this transaction with your wallet to complete the swap'
          }

        rescue => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
