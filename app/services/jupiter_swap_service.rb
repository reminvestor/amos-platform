# frozen_string_literal: true

# JupiterSwapService handles token swaps via Jupiter Aggregator on Solana
#
# Jupiter finds the best route across all Solana DEXs:
# - Raydium, Orca, Meteora, Phoenix, etc.
#
# Use cases:
# - Swap AMOS → USDC for stable disbursements
# - Swap AMOS → SOL for gas or trading
# - Swap AMOS → wBTC for Bitcoin exposure
#
# API Docs: https://station.jup.ag/docs/apis/swap-api
class JupiterSwapService
  class SwapError < StandardError; end
  class QuoteError < SwapError; end
  class InsufficientLiquidityError < SwapError; end

  JUPITER_API = 'https://quote-api.jup.ag/v6'
  
  # Common Solana token mints
  TOKEN_MINTS = {
    sol: 'So11111111111111111111111111111111111111112',        # Native SOL (wrapped)
    usdc: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',     # USDC
    usdt: 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',     # USDT
    wbtc: '3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh',     # Wrapped BTC
    bonk: 'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263',     # BONK (meme)
  }.freeze

  # Default slippage in basis points (50 = 0.5%)
  DEFAULT_SLIPPAGE_BPS = 50

  class << self
    # Get AMOS token mint from config
    def amos_mint
      ENV.fetch('SOLANA_TOKEN_MINT')
    end

    # === QUOTES ===

    # Get a swap quote from Jupiter
    # @param input_mint [String] Token to sell
    # @param output_mint [String] Token to buy
    # @param amount [Integer] Amount in smallest units (lamports/token decimals)
    # @param slippage_bps [Integer] Max slippage in basis points
    # @return [Hash] Quote details including route and expected output
    def get_quote(input_mint:, output_mint:, amount:, slippage_bps: DEFAULT_SLIPPAGE_BPS)
      Rails.logger.info "[JUPITER] Getting quote: #{amount} #{input_mint} → #{output_mint}"

      response = HTTParty.get(
        "#{JUPITER_API}/quote",
        query: {
          inputMint: input_mint,
          outputMint: output_mint,
          amount: amount.to_i,
          slippageBps: slippage_bps,
          onlyDirectRoutes: false,
          asLegacyTransaction: false
        },
        timeout: 10
      )

      unless response.success?
        error_msg = response.parsed_response&.dig('error') || response.message
        
        if error_msg.to_s.include?('insufficient liquidity')
          raise InsufficientLiquidityError, "Not enough liquidity for this swap"
        end
        
        raise QuoteError, "Failed to get quote: #{error_msg}"
      end

      quote = response.parsed_response
      
      Rails.logger.info "[JUPITER] Quote received: " \
                        "#{quote['inAmount']} → #{quote['outAmount']} " \
                        "(#{quote['routePlan']&.length || 0} routes)"

      {
        input_mint: quote['inputMint'],
        output_mint: quote['outputMint'],
        input_amount: quote['inAmount'].to_i,
        output_amount: quote['outAmount'].to_i,
        price_impact_pct: quote['priceImpactPct'].to_f,
        slippage_bps: quote['slippageBps'],
        route_plan: quote['routePlan'],
        raw_quote: quote  # Keep for swap execution
      }
    end

    # Get quote for AMOS → USDC
    def quote_amos_to_usdc(amos_amount)
      # Convert human amount to token units (9 decimals)
      amount_in_smallest = (amos_amount * 1_000_000_000).to_i
      
      quote = get_quote(
        input_mint: amos_mint,
        output_mint: TOKEN_MINTS[:usdc],
        amount: amount_in_smallest
      )

      # Convert output back to human readable (USDC has 6 decimals)
      quote[:output_amount_human] = quote[:output_amount].to_f / 1_000_000
      quote[:input_amount_human] = amos_amount
      quote[:rate] = quote[:output_amount_human] / amos_amount
      
      quote
    end

    # Get quote for AMOS → SOL
    def quote_amos_to_sol(amos_amount)
      amount_in_smallest = (amos_amount * 1_000_000_000).to_i
      
      quote = get_quote(
        input_mint: amos_mint,
        output_mint: TOKEN_MINTS[:sol],
        amount: amount_in_smallest
      )

      # SOL has 9 decimals
      quote[:output_amount_human] = quote[:output_amount].to_f / 1_000_000_000
      quote[:input_amount_human] = amos_amount
      quote[:rate] = quote[:output_amount_human] / amos_amount
      
      quote
    end

    # === SWAP EXECUTION ===

    # Get serialized swap transaction from Jupiter
    # User must sign this transaction with their wallet
    def get_swap_transaction(quote:, user_wallet:)
      Rails.logger.info "[JUPITER] Building swap transaction for #{user_wallet}"

      response = HTTParty.post(
        "#{JUPITER_API}/swap",
        headers: { 'Content-Type' => 'application/json' },
        body: {
          quoteResponse: quote[:raw_quote],
          userPublicKey: user_wallet,
          wrapAndUnwrapSol: true,
          dynamicComputeUnitLimit: true,
          prioritizationFeeLamports: 'auto'
        }.to_json,
        timeout: 15
      )

      unless response.success?
        raise SwapError, "Failed to build swap transaction: #{response.message}"
      end

      data = response.parsed_response
      
      {
        swap_transaction: data['swapTransaction'],
        last_valid_block_height: data['lastValidBlockHeight'],
        prioritization_fee_lamports: data['prioritizationFeeLamports']
      }
    end

    # === CONVENIENCE METHODS ===

    # Get current AMOS price in USDC
    def amos_price_usdc
      quote = quote_amos_to_usdc(1.0)
      quote[:output_amount_human]
    rescue => e
      Rails.logger.error "[JUPITER] Failed to get AMOS price: #{e.message}"
      nil
    end

    # Get current AMOS price in SOL
    def amos_price_sol
      quote = quote_amos_to_sol(1.0)
      quote[:output_amount_human]
    rescue => e
      Rails.logger.error "[JUPITER] Failed to get AMOS price: #{e.message}"
      nil
    end

    # Check if liquidity exists for AMOS
    def has_liquidity?
      quote_amos_to_usdc(100)  # Try to quote 100 AMOS
      true
    rescue InsufficientLiquidityError
      false
    rescue => e
      Rails.logger.error "[JUPITER] Liquidity check failed: #{e.message}"
      false
    end

    # Get supported output tokens
    def supported_output_tokens
      TOKEN_MINTS.keys
    end

    # Get mint address for a token symbol
    def mint_for(symbol)
      TOKEN_MINTS[symbol.to_sym] || raise(ArgumentError, "Unknown token: #{symbol}")
    end
  end
end
