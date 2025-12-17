// Emoji, GIF Picker, and @Mentions for Hub Messages
// Provides emoji reactions, emoji posting, Giphy integration, and user mentions

let emojiPickerOpen = false;
let gifPickerOpen = false;
let emojiSearchTimeout = null;
let gifSearchTimeout = null;
let currentReactionMessage = null;
let mentionAutocompleteOpen = false;
let threadParticipants = [];

// Initialize emoji and GIF pickers
function initializeAll() {
  console.log('🎬 Initializing emoji, GIF, reactions, and mentions...');
  initializeEmojiPicker();
  initializeGifPicker();
  initializeMessageReactions();
  initializeMentionAutocomplete();
}

// Only initialize once - use turbo:load for SPA navigation
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeAll);
} else {
  // DOM already loaded
  initializeAll();
}

document.addEventListener('turbo:load', initializeAll);

// ========================================
// EMOJI PICKER
// ========================================

function initializeEmojiPicker() {
  const emojiButton = document.getElementById('emoji-button');
  console.log('🎨 Emoji button found:', emojiButton);
  if (!emojiButton) {
    console.warn('⚠️ Emoji button not found in DOM');
    return;
  }
  
  // Check if already initialized
  if (emojiButton.dataset.initialized === 'true') {
    console.log('🎨 Emoji button already initialized, skipping');
    return;
  }
  
  emojiButton.dataset.initialized = 'true';
  
  emojiButton.addEventListener('click', (e) => {
    e.preventDefault();
    e.stopPropagation();
    console.log('🎨 Emoji button clicked!');
    toggleEmojiPicker(e);
  });
  
  console.log('✅ Emoji button listener attached');
}

function toggleEmojiPicker(event) {
  // Prevent multiple rapid calls
  if (window.emojiPickerToggling) {
    console.log('🎨 Already toggling, ignoring...');
    return;
  }
  window.emojiPickerToggling = true;
  
  const picker = document.getElementById('emoji-picker-popover');
  const button = document.getElementById('emoji-button');
  
  console.log('🎨 Emoji picker element:', picker);
  console.log('🎨 Emoji button:', button);
  console.log('🎨 Current state - open:', emojiPickerOpen);
  
  if (!picker) {
    console.error('❌ Emoji picker popover not found in DOM!');
    window.emojiPickerToggling = false;
    return;
  }
  
  emojiPickerOpen = !emojiPickerOpen;
  
  if (emojiPickerOpen) {
    closeGifPicker(); // Close GIF picker if open
    picker.classList.remove('d-none');
    
    // Position picker above the button dynamically
    if (button) {
      const buttonRect = button.getBoundingClientRect();
      const pickerHeight = 400; // max-height
      const pickerWidth = 360;
      
      // Position above the button
      picker.style.bottom = `${window.innerHeight - buttonRect.top + 10}px`;
      
      // Center horizontally or align with button
      const centerX = window.innerWidth / 2 - pickerWidth / 2;
      picker.style.left = `${Math.max(20, centerX)}px`;
      picker.style.transform = 'none';
      
      console.log('📍 Positioned emoji picker at:', {
        bottom: picker.style.bottom,
        left: picker.style.left
      });
    }
    
    console.log('✅ Emoji picker opened, classes:', picker.className);
    
    // Setup click-outside handler after a brief delay to prevent immediate close
    setTimeout(() => {
      const clickOutsideHandler = (e) => {
        if (picker && !picker.contains(e.target) && e.target !== button && !button.contains(e.target)) {
          closeEmojiPicker();
          document.removeEventListener('click', clickOutsideHandler);
        }
      };
      document.addEventListener('click', clickOutsideHandler);
    }, 100);
    
    setTimeout(() => {
      document.getElementById('emoji-search-input')?.focus();
    }, 100);
  } else {
    picker.classList.add('d-none');
    console.log('✅ Emoji picker closed');
  }
  
  // Reset toggle lock after animation
  setTimeout(() => {
    window.emojiPickerToggling = false;
  }, 200);
}

function closeEmojiPicker() {
  const picker = document.getElementById('emoji-picker-popover');
  if (picker) {
    picker.classList.add('d-none');
    emojiPickerOpen = false;
  }
}

function insertEmoji(emoji) {
  const messageInput = document.getElementById('message-input');
  if (!messageInput) return;
  
  const cursorPos = messageInput.selectionStart;
  const textBefore = messageInput.value.substring(0, cursorPos);
  const textAfter = messageInput.value.substring(cursorPos);
  
  messageInput.value = textBefore + emoji + textAfter;
  messageInput.selectionStart = messageInput.selectionEnd = cursorPos + emoji.length;
  messageInput.focus();
  
  // Auto-resize textarea
  messageInput.style.height = 'auto';
  messageInput.style.height = messageInput.scrollHeight + 'px';
}

function filterEmojis(searchTerm) {
  // Simple emoji filtering - can be enhanced with emoji names/keywords
  const categories = document.querySelectorAll('.emoji-category');
  
  if (!searchTerm.trim()) {
    categories.forEach(cat => cat.style.display = 'block');
    return;
  }
  
  // Hide all categories initially
  categories.forEach(cat => {
    const title = cat.querySelector('.emoji-category-title').textContent.toLowerCase();
    const matches = title.includes(searchTerm.toLowerCase());
    cat.style.display = matches ? 'block' : 'none';
  });
}

// ========================================
// GIF PICKER
// ========================================

function initializeGifPicker() {
  const gifButton = document.getElementById('gif-button');
  if (!gifButton) return;
  
  gifButton.addEventListener('click', (e) => {
    e.preventDefault();
    e.stopPropagation();
    toggleGifPicker();
  });
  
  // Close picker when clicking outside
  document.addEventListener('click', (e) => {
    const picker = document.getElementById('gif-picker-popover');
    const button = document.getElementById('gif-button');
    
    if (picker && !picker.contains(e.target) && e.target !== button && !button.contains(e.target)) {
      closeGifPicker();
    }
  });
}

function toggleGifPicker(event) {
  // Prevent multiple rapid calls
  if (window.gifPickerToggling) {
    console.log('🖼️ Already toggling, ignoring...');
    return;
  }
  window.gifPickerToggling = true;
  
  const picker = document.getElementById('gif-picker-popover');
  const button = document.getElementById('gif-button');
  
  console.log('🖼️ GIF picker element:', picker);
  console.log('🖼️ GIF button:', button);
  console.log('🖼️ Current state - open:', gifPickerOpen);
  
  if (!picker) {
    console.error('❌ GIF picker popover not found in DOM!');
    window.gifPickerToggling = false;
    return;
  }
  
  gifPickerOpen = !gifPickerOpen;
  
  if (gifPickerOpen) {
    closeEmojiPicker(); // Close emoji picker if open
    picker.classList.remove('d-none');
    
    // Position picker above the button dynamically
    if (button) {
      const buttonRect = button.getBoundingClientRect();
      const pickerHeight = 500; // max-height
      const pickerWidth = 400;
      
      // Position above the button
      picker.style.bottom = `${window.innerHeight - buttonRect.top + 10}px`;
      
      // Center horizontally or align with button
      const centerX = window.innerWidth / 2 - pickerWidth / 2;
      picker.style.left = `${Math.max(20, centerX)}px`;
      picker.style.transform = 'none';
      
      console.log('📍 Positioned GIF picker at:', {
        bottom: picker.style.bottom,
        left: picker.style.left
      });
    }
    
    console.log('✅ GIF picker opened, classes:', picker.className);
    
    // Setup click-outside handler after a brief delay to prevent immediate close
    setTimeout(() => {
      const clickOutsideHandler = (e) => {
        if (picker && !picker.contains(e.target) && e.target !== button && !button.contains(e.target)) {
          console.log('📍 Closing GIF picker - clicked outside');
          closeGifPicker();
          document.removeEventListener('click', clickOutsideHandler);
        }
      };
      document.addEventListener('click', clickOutsideHandler);
    }, 100);
    
    setTimeout(() => {
      document.getElementById('gif-search-input')?.focus();
    }, 100);
    
    // Load trending GIFs
    const gifGrid = document.getElementById('gif-grid');
    if (gifGrid && !gifGrid.querySelector('.gif-item')) {
      searchGifs('excited'); // Default search
    }
  } else {
    picker.classList.add('d-none');
    console.log('✅ GIF picker closed');
  }
  
  // Reset toggle lock after animation
  setTimeout(() => {
    window.gifPickerToggling = false;
  }, 200);
}

function closeGifPicker() {
  const picker = document.getElementById('gif-picker-popover');
  if (picker) {
    picker.classList.add('d-none');
    gifPickerOpen = false;
  }
}

function searchGifs(query) {
  if (gifSearchTimeout) clearTimeout(gifSearchTimeout);
  
  if (!query.trim()) {
    document.getElementById('gif-grid').innerHTML = '<div class="gif-loading">Type to search for GIFs...</div>';
    return;
  }
  
  // Debounce search
  gifSearchTimeout = setTimeout(() => {
    performGifSearch(query);
  }, 300);
}

async function performGifSearch(query) {
  const gifGrid = document.getElementById('gif-grid');
  if (!gifGrid) return;
  
  gifGrid.innerHTML = '<div class="gif-loading"><div class="spinner-border spinner-border-sm me-2"></div>Searching...</div>';
  
  try {
    const response = await fetch(`/hub/giphy/search?q=${encodeURIComponent(query)}&limit=20`);
    const data = await response.json();
    
    if (data.success && data.gifs && data.gifs.length > 0) {
      displayGifs(data.gifs);
    } else if (data.setup_required) {
      // Giphy API not configured
      gifGrid.innerHTML = `
        <div class="gif-setup-required">
          <i data-lucide="alert-circle" style="width: 32px; height: 32px; color: var(--accent-yellow); margin-bottom: 1rem;"></i>
          <p style="color: var(--text-primary); font-weight: 600; margin-bottom: 0.5rem;">Giphy Not Configured</p>
          <p style="color: var(--text-muted); font-size: 0.875rem; margin-bottom: 1rem;">
            To use GIFs, you'll need to configure a Giphy API key.
          </p>
          <a href="https://developers.giphy.com/" target="_blank" class="btn btn-sm btn-outline-primary">
            Get Free API Key
          </a>
          <p style="color: var(--text-muted); font-size: 0.75rem; margin-top: 1rem;">
            Then add it to Rails credentials:<br>
            <code>giphy: { api_key: "YOUR_KEY" }</code>
          </p>
        </div>
      `;
      
      // Reinitialize Lucide icons for the alert icon
      if (typeof lucide !== 'undefined') {
        lucide.createIcons();
      }
    } else if (data.gifs && data.gifs.length === 0) {
      gifGrid.innerHTML = '<div class="gif-empty">No GIFs found. Try a different search term!</div>';
    } else {
      gifGrid.innerHTML = `<div class="gif-error">${data.error || 'Failed to load GIFs'}</div>`;
    }
  } catch (error) {
    console.error('GIF search error:', error);
    gifGrid.innerHTML = '<div class="gif-error">Network error. Please check your connection.</div>';
  }
}

function displayGifs(gifs) {
  const gifGrid = document.getElementById('gif-grid');
  if (!gifGrid) return;
  
  gifGrid.innerHTML = gifs.map(gif => `
    <button class="gif-item" onclick="selectGif('${gif.url}', '${gif.title}')" type="button">
      <img src="${gif.url}" alt="${gif.title}" loading="lazy">
    </button>
  `).join('');
}

function selectGif(url, title) {
  // Send GIF as a message
  const messageInput = document.getElementById('message-input');
  if (messageInput) {
    // Store GIF URL in a hidden field or send directly
    sendGifMessage(url, title);
  }
  closeGifPicker();
}

function sendGifMessage(gifUrl, gifTitle) {
  console.log('🖼️ Sending GIF:', gifTitle);
  
  // Check if we're in a Hub channel/thread
  const activeChannel = document.querySelector('.hub-item.active[data-channel-id]');
  
  if (activeChannel && activeChannel.dataset.channelId) {
    // Send to Hub channel
    console.log('🖼️ Sending to Hub channel:', activeChannel.dataset.channelId);
    sendHubGifMessage(gifUrl, gifTitle);
  } else {
    // Send as regular message (Amos chat or non-channel view)
    console.log('🖼️ Sending to regular chat');
    const messageInput = document.getElementById('message-input');
    if (messageInput) {
      messageInput.value = `![${gifTitle}](${gifUrl})`;
      // Trigger the send button
      const sendButton = document.getElementById('send-button');
      if (sendButton) {
        sendButton.click();
      }
      console.log('✅ GIF message queued');
    }
  }
}

async function sendHubGifMessage(gifUrl, gifTitle) {
  // Get active channel
  const activeChannel = document.querySelector('.hub-item.active[data-channel-id]');
  if (!activeChannel) {
    console.error('❌ No active Hub channel found');
    return;
  }
  
  const channelId = activeChannel.dataset.channelId;
  if (!channelId) {
    console.error('❌ No channel ID');
    return;
  }
  
  console.log('🖼️ Sending to Hub channel ID:', channelId);
  
  try {
    // Get CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ||
                      document.querySelector('[name="csrf-token"]')?.content ||
                      document.querySelector('input[name="authenticity_token"]')?.value;
    
    if (!csrfToken) {
      console.error('❌ CSRF token not found');
      return;
    }
    
    const response = await fetch(`/hub/channels/${channelId}/messages`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      body: JSON.stringify({
        content: gifUrl,
        message_type: 'gif',
        metadata: { gif_title: gifTitle }
      })
    });
    
    const data = await response.json();
    if (data.success) {
      console.log('GIF sent successfully');
    }
  } catch (error) {
    console.error('Failed to send GIF:', error);
  }
}

// ========================================
// MESSAGE REACTIONS
// ========================================

function initializeMessageReactions() {
  console.log('😊 Initializing message reactions...');
  
  // Use event delegation on message container
  const chatContainer = document.getElementById('chat-messages');
  console.log('😊 Chat container found:', chatContainer);
  
  if (!chatContainer) {
    console.warn('⚠️ Chat messages container not found');
    return;
  }
  
  // Check if already initialized
  if (chatContainer.dataset.reactionsInitialized === 'true') {
    console.log('😊 Message reactions already initialized, skipping');
    return;
  }
  
  chatContainer.dataset.reactionsInitialized = 'true';
  
  // Add hover handler for showing reaction buttons
  chatContainer.addEventListener('mouseover', (e) => {
    const messageElement = e.target.closest('.hub-message') || e.target.closest('.message-bubble');
    if (messageElement) {
      showReactionButton(messageElement);
    }
  });
  
  console.log('✅ Message reactions initialized');
}

function showReactionButton(messageElement) {
  if (!messageElement) {
    return;
  }
  
  // Check if reaction button already exists
  if (messageElement.querySelector('.message-reaction-trigger')) {
    return;
  }
  
  const messageId = messageElement.dataset.messageId;
  if (!messageId) {
    return;
  }
  
  // Only add reactions to Hub messages (not Scout messages)
  const isHubMessage = messageElement.classList.contains('hub-message') || 
                       document.getElementById('workspace')?.dataset?.inTeamSpace === 'true';
  
  if (!isHubMessage) {
    console.log('😊 Skipping reaction button - not a Hub message');
    return;
  }
  
  console.log('😊 Adding reaction button to Hub message:', messageId);
  
  // Create reaction button
  const reactionBtn = document.createElement('button');
  reactionBtn.className = 'message-reaction-trigger';
  reactionBtn.type = 'button';
  reactionBtn.innerHTML = '😊';
  reactionBtn.title = 'Add reaction';
  reactionBtn.style.cssText = `
    position: absolute;
    top: -12px;
    right: 10px;
    background: var(--bg-card);
    border: 1px solid var(--border-primary);
    border-radius: 0.375rem;
    padding: 0.25rem 0.5rem;
    cursor: pointer;
    font-size: 1rem;
    z-index: 100;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
  `;
  
  reactionBtn.onclick = (e) => {
    e.preventDefault();
    e.stopPropagation();
    showReactionPicker(messageId, reactionBtn);
  };
  
  messageElement.style.position = 'relative'; // Ensure message is positioned for absolute button
  messageElement.appendChild(reactionBtn);
  
  console.log('✅ Reaction button added');
}

function showReactionPicker(messageId, triggerButton) {
  currentReactionMessage = messageId;
  
  // Quick reaction picker with common emojis
  const quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🎉', '🔥', '👏'];
  
  // Remove any existing reaction picker
  document.querySelectorAll('.reaction-picker-popup').forEach(el => el.remove());
  
  // Create picker
  const picker = document.createElement('div');
  picker.className = 'reaction-picker-popup';
  picker.innerHTML = quickEmojis.map(emoji => 
    `<button class="reaction-emoji-btn" onclick="addReactionToMessage('${messageId}', '${emoji}')">${emoji}</button>`
  ).join('');
  
  // Position near trigger button
  const rect = triggerButton.getBoundingClientRect();
  picker.style.position = 'fixed';
  picker.style.bottom = `${window.innerHeight - rect.top + 5}px`;
  picker.style.left = `${rect.left}px`;
  
  document.body.appendChild(picker);
  
  // Close on click outside
  setTimeout(() => {
    document.addEventListener('click', function closePickerHandler(e) {
      if (!picker.contains(e.target) && e.target !== triggerButton) {
        picker.remove();
        document.removeEventListener('click', closePickerHandler);
      }
    });
  }, 0);
}

async function addReactionToMessage(messageId, emoji) {
  console.log('💬 Adding reaction:', emoji, 'to message:', messageId);
  
  try {
    // Get CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ||
                      document.querySelector('[name="csrf-token"]')?.content ||
                      document.querySelector('input[name="authenticity_token"]')?.value;
    
    if (!csrfToken) {
      console.error('❌ CSRF token not found');
      return;
    }
    
    const response = await fetch(`/hub/messages/${messageId}/react`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      body: JSON.stringify({ emoji: emoji })
    });
    
    const data = await response.json();
    if (data.success) {
      console.log('✅ Reaction added successfully');
      updateMessageReactions(messageId, data.reactions);
    } else {
      console.error('❌ Failed to add reaction:', data);
    }
  } catch (error) {
    console.error('Failed to add reaction:', error);
  }
  
  // Close reaction picker
  document.querySelectorAll('.reaction-picker-popup').forEach(el => el.remove());
}

async function removeReactionFromMessage(messageId, emoji) {
  console.log('💬 Removing reaction:', emoji, 'from message:', messageId);
  
  try {
    // Get CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ||
                      document.querySelector('[name="csrf-token"]')?.content ||
                      document.querySelector('input[name="authenticity_token"]')?.value;
    
    if (!csrfToken) {
      console.error('❌ CSRF token not found');
      return;
    }
    
    const response = await fetch(`/hub/messages/${messageId}/react`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      body: JSON.stringify({ emoji: emoji })
    });
    
    const data = await response.json();
    if (data.success) {
      console.log('✅ Reaction removed successfully');
      updateMessageReactions(messageId, data.reactions);
    }
  } catch (error) {
    console.error('Failed to remove reaction:', error);
  }
}

function updateMessageReactions(messageId, reactions) {
  const messageElement = document.querySelector(`[data-message-id="${messageId}"]`);
  if (!messageElement) return;
  
  // Find or create reactions container
  let reactionsContainer = messageElement.querySelector('.message-reactions');
  if (!reactionsContainer) {
    reactionsContainer = document.createElement('div');
    reactionsContainer.className = 'message-reactions';
    messageElement.appendChild(reactionsContainer);
  }
  
  // Update reactions display
  if (reactions && reactions.length > 0) {
    reactionsContainer.innerHTML = reactions.map(reaction => {
      const currentUserId = getCurrentUserId();
      const userReacted = reaction.user_ids.includes(currentUserId);
      
      return `
        <button class="reaction-bubble ${userReacted ? 'user-reacted' : ''}" 
                onclick="toggleReaction(${messageId}, '${reaction.emoji}', ${userReacted})"
                title="${reaction.count} reaction${reaction.count > 1 ? 's' : ''}">
          <span class="reaction-emoji">${reaction.emoji}</span>
          <span class="reaction-count">${reaction.count}</span>
        </button>
      `;
    }).join('');
    reactionsContainer.style.display = 'flex';
  } else {
    reactionsContainer.innerHTML = '';
    reactionsContainer.style.display = 'none';
  }
}

function toggleReaction(messageId, emoji, userHasReacted) {
  if (userHasReacted) {
    removeReactionFromMessage(messageId, emoji);
  } else {
    addReactionToMessage(messageId, emoji);
  }
}

function getCurrentUserId() {
  // Get from data attribute or meta tag
  const workspace = document.getElementById('workspace');
  return workspace?.dataset?.userId || 
         document.querySelector('meta[name="user-id"]')?.content;
}

// Export functions to window for onclick handlers
window.insertEmoji = insertEmoji;
window.filterEmojis = filterEmojis;
window.closeEmojiPicker = closeEmojiPicker;
window.toggleEmojiPicker = toggleEmojiPicker;

// ========================================
// GIF PICKER
// ========================================

function initializeGifPicker() {
  const gifButton = document.getElementById('gif-button');
  if (!gifButton) return;
  
  gifButton.addEventListener('click', (e) => {
    e.preventDefault();
    e.stopPropagation();
    toggleGifPicker();
  });
  
  // Close picker when clicking outside
  document.addEventListener('click', (e) => {
    const picker = document.getElementById('gif-picker-popover');
    const button = document.getElementById('gif-button');
    
    if (picker && !picker.contains(e.target) && e.target !== button && !button.contains(e.target)) {
      closeGifPicker();
    }
  });
}

// Export GIF functions
window.searchGifs = searchGifs;
window.selectGif = selectGif;
window.closeGifPicker = closeGifPicker;
window.toggleGifPicker = toggleGifPicker;
window.addReactionToMessage = addReactionToMessage;
window.removeReactionFromMessage = removeReactionFromMessage;
window.toggleReaction = toggleReaction;

// ========================================
// @MENTIONS AUTOCOMPLETE
// ========================================

function initializeMentionAutocomplete() {
  const messageInput = document.getElementById('message-input');
  if (!messageInput) return;
  
  // Detect @ symbol and show autocomplete
  messageInput.addEventListener('input', (e) => {
    handleMentionInput(e);
  });
  
  // Handle arrow keys and enter in autocomplete
  messageInput.addEventListener('keydown', (e) => {
    if (mentionAutocompleteOpen) {
      handleMentionKeyboard(e);
    }
  });
  
  // Close autocomplete on click outside
  document.addEventListener('click', (e) => {
    const autocomplete = document.getElementById('mention-autocomplete');
    if (autocomplete && !autocomplete.contains(e.target) && e.target !== messageInput) {
      closeMentionAutocomplete();
    }
  });
  
  console.log('✅ Mention autocomplete initialized');
}

function handleMentionInput(e) {
  const input = e.target;
  const text = input.value;
  const cursorPos = input.selectionStart;
  
  // Find the word before cursor
  const textBeforeCursor = text.substring(0, cursorPos);
  const mentionMatch = textBeforeCursor.match(/@([\w.]*)$/);
  
  if (mentionMatch) {
    const searchTerm = mentionMatch[1];
    showMentionAutocomplete(searchTerm, cursorPos);
  } else {
    closeMentionAutocomplete();
  }
}

function showMentionAutocomplete(searchTerm, cursorPos) {
  // Load thread participants if not already loaded
  if (threadParticipants.length === 0) {
    loadThreadParticipants();
  }
  
  // Filter participants by search term
  const filtered = threadParticipants.filter(p => {
    const fullName = p.name.toLowerCase();
    const email = p.email?.toLowerCase() || '';
    const search = searchTerm.toLowerCase();
    return fullName.includes(search) || email.includes(search);
  });
  
  if (filtered.length === 0) {
    closeMentionAutocomplete();
    return;
  }
  
  // Create or update autocomplete UI
  let autocomplete = document.getElementById('mention-autocomplete');
  if (!autocomplete) {
    autocomplete = document.createElement('div');
    autocomplete.id = 'mention-autocomplete';
    autocomplete.className = 'mention-autocomplete';
    document.body.appendChild(autocomplete);
  }
  
  // Position near input
  const messageInput = document.getElementById('message-input');
  const rect = messageInput.getBoundingClientRect();
  autocomplete.style.left = `${rect.left}px`;
  autocomplete.style.bottom = `${window.innerHeight - rect.top + 10}px`;
  
  // Render suggestions
  autocomplete.innerHTML = filtered.map((participant, index) => `
    <div class="mention-suggestion ${index === 0 ? 'selected' : ''}" 
         data-index="${index}"
         data-user-id="${participant.id}"
         data-user-name="${participant.name}"
         onclick="selectMention('${participant.name}', ${participant.id})">
      <div class="mention-avatar">${participant.name.charAt(0).toUpperCase()}</div>
      <div class="mention-info">
        <div class="mention-name">${participant.name}</div>
        ${participant.role ? `<div class="mention-role">${participant.role}</div>` : ''}
      </div>
    </div>
  `).join('');
  
  autocomplete.classList.remove('d-none');
  mentionAutocompleteOpen = true;
}

function closeMentionAutocomplete() {
  const autocomplete = document.getElementById('mention-autocomplete');
  if (autocomplete) {
    autocomplete.classList.add('d-none');
  }
  mentionAutocompleteOpen = false;
}

function handleMentionKeyboard(e) {
  const autocomplete = document.getElementById('mention-autocomplete');
  if (!autocomplete) return;
  
  const suggestions = autocomplete.querySelectorAll('.mention-suggestion');
  const selected = autocomplete.querySelector('.mention-suggestion.selected');
  const selectedIndex = Array.from(suggestions).indexOf(selected);
  
  switch(e.key) {
    case 'ArrowDown':
      e.preventDefault();
      if (selectedIndex < suggestions.length - 1) {
        selected?.classList.remove('selected');
        suggestions[selectedIndex + 1].classList.add('selected');
      }
      break;
      
    case 'ArrowUp':
      e.preventDefault();
      if (selectedIndex > 0) {
        selected?.classList.remove('selected');
        suggestions[selectedIndex - 1].classList.add('selected');
      }
      break;
      
    case 'Enter':
    case 'Tab':
      e.preventDefault();
      if (selected) {
        const userName = selected.dataset.userName;
        const userId = selected.dataset.userId;
        selectMention(userName, userId);
      }
      break;
      
    case 'Escape':
      e.preventDefault();
      closeMentionAutocomplete();
      break;
  }
}

function selectMention(userName, userId) {
  const messageInput = document.getElementById('message-input');
  if (!messageInput) return;
  
  const text = messageInput.value;
  const cursorPos = messageInput.selectionStart;
  const textBeforeCursor = text.substring(0, cursorPos);
  const textAfterCursor = text.substring(cursorPos);
  
  // Replace @partial with @"Full Name" (use quotes for names with spaces)
  const mentionMatch = textBeforeCursor.match(/@([\w.]*)$/);
  if (mentionMatch) {
    const mentionText = userName.includes(' ') ? `@"${userName}"` : `@${userName.replace(' ', '.')}`;
    const beforeMention = textBeforeCursor.substring(0, textBeforeCursor.length - mentionMatch[0].length);
    messageInput.value = beforeMention + mentionText + ' ' + textAfterCursor;
    
    const newCursorPos = beforeMention.length + mentionText.length + 1;
    messageInput.selectionStart = messageInput.selectionEnd = newCursorPos;
    messageInput.focus();
  }
  
  closeMentionAutocomplete();
}

async function loadThreadParticipants() {
  // Get active thread participants
  const activeChannel = document.querySelector('.hub-item.active');
  if (!activeChannel) return;
  
  const threadId = activeChannel.dataset.threadId;
  const channelId = activeChannel.dataset.channelId;
  
  try {
    let url;
    if (channelId) {
      // Load from channel
      const response = await fetch(`/hub/channels/${channelId}/participants`);
      const data = await response.json();
      threadParticipants = data.participants || [];
    } else if (threadId) {
      // Load from thread
      const response = await fetch(`/hub/thread/${threadId}/participants`);
      const data = await response.json();
      threadParticipants = data.participants || [];
    }
  } catch (error) {
    console.error('Failed to load participants:', error);
    threadParticipants = [];
  }
}

// Export mention functions
window.selectMention = selectMention;
window.closeMentionAutocomplete = closeMentionAutocomplete;

console.log('✅ Emoji, GIF Picker & Mentions initialized');

// Debug helper - test if pickers can be toggled manually
window.testEmojiPicker = function() {
  console.log('🧪 Testing emoji picker...');
  const button = document.getElementById('emoji-button');
  const popover = document.getElementById('emoji-picker-popover');
  console.log('Button:', button);
  console.log('Popover:', popover);
  console.log('Popover classes:', popover?.className);
  if (popover) {
    popover.classList.toggle('d-none');
    console.log('Toggled! New classes:', popover.className);
  }
};

window.testGifPicker = function() {
  console.log('🧪 Testing GIF picker...');
  const button = document.getElementById('gif-button');
  const popover = document.getElementById('gif-picker-popover');
  console.log('Button:', button);
  console.log('Popover:', popover);
  console.log('Popover classes:', popover?.className);
  if (popover) {
    popover.classList.toggle('d-none');
    console.log('Toggled! New classes:', popover.className);
  }
};

console.log('💡 Debug helpers available: testEmojiPicker() and testGifPicker()');

