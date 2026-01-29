// Solana Wallet Integration for AMOS Platform
// Supports: Phantom, Solflare, and other Solana wallets

class AmosWallet {
  constructor() {
    this.provider = null;
    this.publicKey = null;
    this.connected = false;
    this.listeners = {};
  }

  // Check if Phantom is installed
  isPhantomInstalled() {
    return window.solana && window.solana.isPhantom;
  }

  // Check if any Solana wallet is available
  isSolanaAvailable() {
    return !!window.solana;
  }

  // Get the wallet provider
  getProvider() {
    if ('phantom' in window) {
      const provider = window.phantom?.solana;
      if (provider?.isPhantom) {
        return provider;
      }
    }
    
    if (window.solana) {
      return window.solana;
    }

    return null;
  }

  // Connect to wallet
  async connect() {
    try {
      const provider = this.getProvider();
      
      if (!provider) {
        throw new Error('No Solana wallet found. Please install Phantom.');
      }

      const response = await provider.connect();
      this.provider = provider;
      this.publicKey = response.publicKey.toString();
      this.connected = true;

      // Set up disconnect listener
      provider.on('disconnect', () => {
        this.handleDisconnect();
      });

      // Set up account change listener
      provider.on('accountChanged', (publicKey) => {
        if (publicKey) {
          this.publicKey = publicKey.toString();
          this.emit('accountChanged', this.publicKey);
        } else {
          this.handleDisconnect();
        }
      });

      this.emit('connected', this.publicKey);
      return this.publicKey;

    } catch (error) {
      console.error('Wallet connection failed:', error);
      throw error;
    }
  }

  // Disconnect from wallet
  async disconnect() {
    if (this.provider) {
      await this.provider.disconnect();
    }
    this.handleDisconnect();
  }

  handleDisconnect() {
    this.provider = null;
    this.publicKey = null;
    this.connected = false;
    this.emit('disconnected');
  }

  // Sign a message for verification
  async signMessage(message) {
    if (!this.provider || !this.connected) {
      throw new Error('Wallet not connected');
    }

    try {
      const encodedMessage = new TextEncoder().encode(message);
      const signedMessage = await this.provider.signMessage(encodedMessage, 'utf8');
      
      // Convert signature to base58
      const signature = this.toBase58(signedMessage.signature);
      
      return {
        message: message,
        signature: signature,
        publicKey: this.publicKey
      };
    } catch (error) {
      console.error('Message signing failed:', error);
      throw error;
    }
  }

  // Connect wallet to AMOS platform
  async connectToPlatform() {
    if (!this.connected) {
      await this.connect();
    }

    // Get verification message from server
    const response = await fetch('/api/v1/wallet/connect', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      },
      body: JSON.stringify({
        wallet_address: this.publicKey
      })
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || 'Failed to get verification message');
    }

    // Sign the verification message
    const signed = await this.signMessage(data.message);

    // Submit signed message to server
    const verifyResponse = await fetch('/api/v1/wallet/connect', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      },
      body: JSON.stringify({
        wallet_address: this.publicKey,
        message: signed.message,
        signature: signed.signature
      })
    });

    const verifyData = await verifyResponse.json();

    if (!verifyResponse.ok) {
      throw new Error(verifyData.error || 'Wallet verification failed');
    }

    this.emit('platformConnected', verifyData);
    return verifyData;
  }

  // Disconnect wallet from platform
  async disconnectFromPlatform() {
    const response = await fetch('/api/v1/wallet/disconnect', {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      }
    });

    if (response.ok) {
      await this.disconnect();
    }

    return response.json();
  }

  // Get wallet balance
  async getBalance() {
    const response = await fetch('/api/v1/wallet/balance', {
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      }
    });

    return response.json();
  }

  // Request token claim
  async claimTokens(amount) {
    const response = await fetch('/api/v1/wallet/claim', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      },
      body: JSON.stringify({ amount: amount })
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || 'Claim failed');
    }

    this.emit('claimSubmitted', data);
    return data;
  }

  // Submit deposit transaction
  async submitDeposit(transactionSignature, amount, walletAddress) {
    const response = await fetch('/api/v1/wallet/deposit', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      },
      body: JSON.stringify({
        transaction_signature: transactionSignature,
        amount: amount,
        wallet_address: walletAddress
      })
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || 'Deposit submission failed');
    }

    this.emit('depositSubmitted', data);
    return data;
  }

  // Get transaction history
  async getTransactions() {
    const response = await fetch('/api/v1/wallet/transactions', {
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      }
    });

    return response.json();
  }

  // Get claim status
  async getClaimStatus(claimId) {
    const response = await fetch(`/api/v1/wallet/claim/${claimId}`, {
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      }
    });

    return response.json();
  }

  // Retry failed claim
  async retryClaim(claimId) {
    const response = await fetch(`/api/v1/wallet/claim/${claimId}/retry`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      }
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || 'Retry failed');
    }

    return data;
  }

  // Event handling
  on(event, callback) {
    if (!this.listeners[event]) {
      this.listeners[event] = [];
    }
    this.listeners[event].push(callback);
  }

  off(event, callback) {
    if (this.listeners[event]) {
      this.listeners[event] = this.listeners[event].filter(cb => cb !== callback);
    }
  }

  emit(event, data) {
    if (this.listeners[event]) {
      this.listeners[event].forEach(callback => callback(data));
    }
  }

  // Utility functions
  getCsrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
  }

  // Base58 encoding (simplified)
  toBase58(buffer) {
    const ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    let result = '';
    let num = BigInt('0x' + Array.from(new Uint8Array(buffer)).map(b => b.toString(16).padStart(2, '0')).join(''));
    
    while (num > 0n) {
      const remainder = num % 58n;
      result = ALPHABET[Number(remainder)] + result;
      num = num / 58n;
    }
    
    // Add leading zeros
    for (const byte of new Uint8Array(buffer)) {
      if (byte === 0) {
        result = '1' + result;
      } else {
        break;
      }
    }
    
    return result;
  }

  // Format address for display
  formatAddress(address, chars = 4) {
    if (!address) return '';
    return `${address.slice(0, chars)}...${address.slice(-chars)}`;
  }
}

// Create global instance
window.amosWallet = new AmosWallet();

// Export for module usage
export default AmosWallet;
