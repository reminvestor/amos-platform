# frozen_string_literal: true

module Api
  module V1
    # TokenWalletController handles Solana wallet operations
    #
    # Endpoints:
    # - POST /api/v1/wallet/connect - Connect/verify wallet
    # - GET /api/v1/wallet/balance - Get internal + on-chain balances
    # - POST /api/v1/wallet/claim - Request token claim to wallet
    # - POST /api/v1/wallet/deposit - Submit deposit transaction
    # - GET /api/v1/wallet/transactions - Get claim/deposit history
    class TokenWalletController < Api::V1::BaseController
      before_action :authenticate_user!
      before_action :validate_wallet_address, only: [:connect, :claim]

      # POST /api/v1/wallet/connect
      # Connect a Solana wallet to user account
      def connect
        # Generate verification message
        verification = SolanaTokenService.generate_verification_message(current_user.id)
        
        if params[:signature].present?
          # Verify the signature
          verified = SolanaTokenService.verify_wallet_signature(
            address: params[:wallet_address],
            message: params[:message],
            signature: params[:signature]
          )

          if verified
            current_user.update!(
              solana_wallet_address: params[:wallet_address],
              wallet_verified_at: Time.current,
              wallet_verification_message: params[:message],
              wallet_verification_signature: params[:signature]
            )

            render json: {
              success: true,
              message: 'Wallet connected successfully',
              wallet_address: current_user.solana_wallet_address
            }
          else
            render json: { error: 'Signature verification failed' }, status: :unprocessable_entity
          end
        else
          # Return message for user to sign
          render json: {
            message: verification[:message],
            nonce: verification[:nonce],
            timestamp: verification[:timestamp]
          }
        end
      end

      # DELETE /api/v1/wallet/disconnect
      def disconnect
        current_user.update!(
          solana_wallet_address: nil,
          wallet_verified_at: nil,
          wallet_verification_message: nil,
          wallet_verification_signature: nil
        )

        render json: { success: true, message: 'Wallet disconnected' }
      end

      # GET /api/v1/wallet/balance
      def balance
        internal_balance = current_user.token_stakes.active.sum(:current_amount)
        pending_claims = TokenClaim.for_user(current_user)
                                   .where(status: %w[pending validated processing])
                                   .sum(:amount)
        claimable_balance = [internal_balance - pending_claims, 0].max

        on_chain_balance = 0
        if current_user.solana_wallet_address.present?
          begin
            on_chain_balance = SolanaTokenService.get_token_balance(current_user.solana_wallet_address)
          rescue SolanaTokenService::SolanaError => e
            Rails.logger.warn "[WALLET] Failed to get on-chain balance: #{e.message}"
          end
        end

        render json: {
          internal_balance: internal_balance.round(4),
          claimable_balance: claimable_balance.round(4),
          pending_claims: pending_claims.round(4),
          on_chain_balance: on_chain_balance.round(4),
          total_balance: (internal_balance + on_chain_balance).round(4),
          wallet_connected: current_user.solana_wallet_address.present?,
          wallet_address: current_user.solana_wallet_address,
          minimum_claim: TokenClaim::MINIMUM_CLAIM,
          claim_fee_rate: TokenClaim::PLATFORM_FEE_RATE
        }
      end

      # POST /api/v1/wallet/claim
      # Request token claim to connected wallet
      def claim
        unless current_user.solana_wallet_address.present?
          return render json: { error: 'No wallet connected' }, status: :unprocessable_entity
        end

        amount = params[:amount].to_f

        if amount < TokenClaim::MINIMUM_CLAIM
          return render json: { 
            error: "Minimum claim is #{TokenClaim::MINIMUM_CLAIM} tokens" 
          }, status: :unprocessable_entity
        end

        # Create claim request
        claim = TokenClaim.create!(
          user: current_user,
          entity: current_user.entity,
          amount: amount,
          wallet_address: current_user.solana_wallet_address,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        # Queue for processing
        ProcessTokenClaimJob.perform_later(claim.id)

        render json: {
          success: true,
          claim_id: claim.id,
          amount: claim.amount,
          net_amount: claim.net_amount,
          platform_fee: claim.platform_fee,
          status: claim.status,
          wallet_address: claim.wallet_address,
          message: 'Claim submitted. Processing will begin shortly.'
        }, status: :created
      end

      # POST /api/v1/wallet/deposit
      # Submit a deposit transaction for verification
      def deposit
        unless params[:transaction_signature].present?
          return render json: { error: 'Transaction signature required' }, status: :unprocessable_entity
        end

        unless params[:wallet_address].present?
          return render json: { error: 'Wallet address required' }, status: :unprocessable_entity
        end

        amount = params[:amount].to_f
        if amount <= 0
          return render json: { error: 'Invalid amount' }, status: :unprocessable_entity
        end

        # Check for duplicate
        if TokenDeposit.exists?(transaction_signature: params[:transaction_signature])
          return render json: { error: 'Transaction already submitted' }, status: :conflict
        end

        # Create deposit record
        deposit = TokenDeposit.create!(
          user: current_user,
          entity: current_user.entity,
          amount: amount,
          wallet_address: params[:wallet_address],
          transaction_signature: params[:transaction_signature]
        )

        # Queue for verification
        VerifyTokenDepositJob.perform_later(deposit.id)

        render json: {
          success: true,
          deposit_id: deposit.id,
          amount: deposit.amount,
          status: deposit.status,
          transaction_signature: deposit.transaction_signature,
          message: 'Deposit submitted. Verification in progress.'
        }, status: :created
      end

      # GET /api/v1/wallet/transactions
      def transactions
        claims = TokenClaim.for_user(current_user)
                           .recent
                           .limit(50)
                           .map do |c|
          {
            id: c.id,
            type: 'claim',
            amount: c.amount,
            net_amount: c.net_amount,
            status: c.status,
            wallet_address: c.wallet_address,
            transaction_signature: c.transaction_signature,
            created_at: c.created_at,
            confirmed_at: c.confirmed_at,
            error_message: c.error_message
          }
        end

        deposits = TokenDeposit.for_user(current_user)
                               .recent
                               .limit(50)
                               .map do |d|
          {
            id: d.id,
            type: 'deposit',
            amount: d.amount,
            status: d.status,
            wallet_address: d.wallet_address,
            transaction_signature: d.transaction_signature,
            created_at: d.created_at,
            confirmed_at: d.confirmed_at,
            error_message: d.error_message
          }
        end

        all_transactions = (claims + deposits).sort_by { |t| t[:created_at] }.reverse

        render json: {
          transactions: all_transactions,
          total_claimed: TokenClaim.for_user(current_user).completed.sum(:amount),
          total_deposited: TokenDeposit.for_user(current_user).completed.sum(:amount)
        }
      end

      # GET /api/v1/wallet/claim/:id
      def claim_status
        claim = TokenClaim.for_user(current_user).find(params[:id])

        render json: {
          id: claim.id,
          amount: claim.amount,
          net_amount: claim.net_amount,
          status: claim.status,
          wallet_address: claim.wallet_address,
          transaction_signature: claim.transaction_signature,
          created_at: claim.created_at,
          confirmed_at: claim.confirmed_at,
          error_message: claim.error_message,
          retryable: claim.retryable?
        }
      end

      # POST /api/v1/wallet/claim/:id/retry
      def retry_claim
        claim = TokenClaim.for_user(current_user).find(params[:id])

        unless claim.retryable?
          return render json: { error: 'Claim cannot be retried' }, status: :unprocessable_entity
        end

        claim.retry!
        ProcessTokenClaimJob.perform_later(claim.id)

        render json: {
          success: true,
          claim_id: claim.id,
          status: claim.status,
          message: 'Claim retry queued'
        }
      end

      private

      def validate_wallet_address
        address = params[:wallet_address]
        return unless address.present?

        unless SolanaTokenService.valid_address?(address)
          render json: { error: 'Invalid Solana wallet address' }, status: :unprocessable_entity
        end
      end
    end
  end
end
