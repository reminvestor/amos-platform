// Solana Wallet Integration for AMOS Platform
// Supports: Phantom, Solflare, and other Solana wallets
// Includes: Token claims, deposits, and Jupiter swaps

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

      provider.on('disconnect', () => this.handleDisconnect());
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

    const encodedMessage = new TextEncoder().encode(message);
    const signedMessage = await this.provider.signMessage(encodedMessage, 'utf8');
    const signature = this.toBase58(signedMessage.signature);

    return { message, signature, publicKey: this.publicKey };
  }

  // Sign and send a transaction
  async signAndSendTransaction(serializedTransaction) {
    if (!this.provider || !this.connected) {
      throw new Error('Wallet not connected');
    }

    // Decode base64 transaction
    const transaction = this.decodeTransaction(serializedTransaction);
    
    // Sign and send
    const signature = await this.provider.signAndSendTransaction(transaction);
    return signature;
  }

  // === PLATFORM API METHODS ===

  async connectToPlatform() {
    if (!this.connected) {
      await this.connect();
    }

    // Get verification message
    const response = await this.apiPost('/api/v1/wallet/connect', {
      wallet_address: this.publicKey
    });

    if (response.message && !response.success) {
      // Sign the message
      const signed = await this.signMessage(response.message);

      // Submit signature
      const verifyResponse = await this.apiPost('/api/v1/wallet/connect', {
        wallet_address: this.publicKey,
        message: signed.message,
        signature: signed.signature
      });

      this.emit('platformConnected', verifyResponse);
      return verifyResponse;
    }

    return response;
  }

  async disconnectFromPlatform() {
    const response = await this.apiDelete('/api/v1/wallet/disconnect');
    await this.disconnect();
    return response;
  }

  async getBalance() {
    return this.apiGet('/api/v1/wallet/balance');
  }

  async claimTokens(amount, disbursementCurrency = 'amos') {
    const response = await this.apiPost('/api/v1/wallet/claim', { 
      amount,
      disbursement_currency: disbursementCurrency
    });
    this.emit('claimSubmitted', response);
    return response;
  }

  async submitDeposit(transactionSignature, amount, walletAddress) {
    const response = await this.apiPost('/api/v1/wallet/deposit', {
      transaction_signature: transactionSignature,
      amount,
      wallet_address: walletAddress
    });
    this.emit('depositSubmitted', response);
    return response;
  }

  async getTransactions() {
    return this.apiGet('/api/v1/wallet/transactions');
  }

  // === SWAP METHODS ===

  async getSwapQuote(amount, outputCurrency = 'usdc') {
    return this.apiGet(`/api/v1/swap/quote?amount=${amount}&output_currency=${outputCurrency}`);
  }

  async getAmosPrice() {
    return this.apiGet('/api/v1/swap/price');
  }

  async getSupportedTokens() {
    return this.apiGet('/api/v1/swap/supported_tokens');
  }

  async prepareSwap(amount, outputCurrency = 'usdc') {
    return this.apiPost('/api/v1/swap/prepare', {
      amount,
      output_currency: outputCurrency
    });
  }

  // Execute a swap (user signs the transaction)
  async executeSwap(amount, outputCurrency = 'usdc') {
    // Get the prepared swap transaction
    const prepared = await this.prepareSwap(amount, outputCurrency);
    
    if (!prepared.swap_transaction) {
      throw new Error('Failed to prepare swap');
    }

    // Sign and send with wallet
    const signature = await this.signAndSendTransaction(prepared.swap_transaction);
    
    this.emit('swapExecuted', {
      signature,
      inputAmount: amount,
      outputAmount: prepared.quote.output_amount,
      outputCurrency
    });

    return {
      signature,
      ...prepared.quote
    };
  }

  // === HELPER METHODS ===

  async apiGet(url) {
    const response = await fetch(url, {
      headers: { 'Content-Type': 'application/json' }
    });
    return response.json();
  }

  async apiPost(url, data) {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      },
      body: JSON.stringify(data)
    });
    return response.json();
  }

  async apiDelete(url) {
    const response = await fetch(url, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      }
    });
    return response.json();
  }

  getCsrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
  }

  // Event handling
  on(event, callback) {
    if (!this.listeners[event]) this.listeners[event] = [];
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

  // Base58 encoding
  toBase58(buffer) {
    const ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    let result = '';
    let num = BigInt('0x' + Array.from(new Uint8Array(buffer)).map(b => b.toString(16).padStart(2, '0')).join(''));
    
    while (num > 0n) {
      const remainder = num % 58n;
      result = ALPHABET[Number(remainder)] + result;
      num = num / 58n;
    }
    
    for (const byte of new Uint8Array(buffer)) {
      if (byte === 0) result = '1' + result;
      else break;
    }
    
    return result;
  }

  // Decode base64 transaction for signing
  decodeTransaction(base64Transaction) {
    const bytes = Uint8Array.from(atob(base64Transaction), c => c.charCodeAt(0));
    return bytes;
  }

  formatAddress(address, chars = 4) {
    if (!address) return '';
    return `${address.slice(0, chars)}...${address.slice(-chars)}`;
  }

  formatAmount(amount, decimals = 4) {
    return Number(amount).toLocaleString(undefined, {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals
    });
  }
}

// Create global instance
window.amosWallet = new AmosWallet();

// Export for module usage
export default AmosWallet;
