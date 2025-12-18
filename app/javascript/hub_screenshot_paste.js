// Hub Screenshot Paste - Inline image pasting for Team Space channels and DMs
// Handles Ctrl/Cmd+V to paste screenshots directly into messages

let hubPendingImages = [];

// Initialize paste handler for Hub
document.addEventListener('DOMContentLoaded', initHubScreenshotPaste);
document.addEventListener('turbo:load', initHubScreenshotPaste);

function initHubScreenshotPaste() {
  // Only initialize if we're in Team Space
  const workspace = document.getElementById('workspace');
  if (!workspace || workspace.dataset.inTeamSpace !== 'true') {
    console.log('📸 Not in Team Space, skipping Hub screenshot paste');
    return;
  }
  
  const messageInput = document.getElementById('message-input');
  if (!messageInput) {
    console.log('📸 Message input not found');
    return;
  }
  
  // Check if already initialized
  if (messageInput.dataset.hubPasteInitialized === 'true') {
    console.log('📸 Hub paste already initialized');
    return;
  }
  
  messageInput.dataset.hubPasteInitialized = 'true';
  
  messageInput.addEventListener('paste', handleHubPaste);
  
  console.log('✅ Hub screenshot paste initialized');
}

async function handleHubPaste(e) {
  const items = e.clipboardData?.items;
  if (!items) return;
  
  for (const item of items) {
    if (item.type.startsWith('image/')) {
      e.preventDefault();
      e.stopPropagation(); // Stop other paste handlers from running
      console.log('📸 Image pasted in Hub');
      
      const file = item.getAsFile();
      if (!file) return;
      
      // Generate unique filename
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      const extension = file.type.split('/')[1] || 'png';
      const renamedFile = new File([file], `screenshot-${timestamp}.${extension}`, { type: file.type });
      
      console.log('📸 Uploading pasted image:', renamedFile.name);
      
      // Upload immediately and get URL
      const imageUrl = await uploadHubImage(renamedFile);
      
      if (imageUrl) {
        // Insert image markdown into message
        const messageInput = document.getElementById('message-input');
        if (messageInput) {
          const currentValue = messageInput.value;
          const imageMarkdown = `![Pasted image](${imageUrl})`;
          messageInput.value = currentValue ? `${currentValue}\n${imageMarkdown}` : imageMarkdown;
          
          // Show preview
          showHubImagePreview(imageUrl, renamedFile.name);
          
          // Auto-resize textarea
          messageInput.style.height = 'auto';
          messageInput.style.height = messageInput.scrollHeight + 'px';
          
          console.log('✅ Image markdown inserted');
        }
      }
      
      return; // Only process first image
    }
  }
}

async function uploadHubImage(file) {
  try {
    // Create FormData for upload - nested under image_asset as the controller expects
    const formData = new FormData();
    formData.append('image_asset[file]', file);
    formData.append('image_asset[title]', file.name);
    formData.append('image_asset[source]', 'hub_upload');
    
    // Get CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ||
                      document.querySelector('[name="csrf-token"]')?.content ||
                      document.querySelector('input[name="authenticity_token"]')?.value;
    
    if (!csrfToken) {
      console.error('❌ CSRF token not found');
      return null;
    }
    
    // Upload to image assets endpoint
    const response = await fetch('/image_assets', {
      method: 'POST',
      headers: {
        'X-CSRF-Token': csrfToken,
        'Accept': 'application/json'
      },
      body: formData
    });
    
    if (response.ok) {
      const data = await response.json();
      console.log('✅ Image uploaded:', data);
      // Get the URL from the response
      const imageUrl = data.image?.url || data.url;
      return imageUrl;
    } else {
      const errorText = await response.text();
      console.error('❌ Upload failed:', response.status, errorText);
      return null;
    }
  } catch (error) {
    console.error('❌ Upload error:', error);
    return null;
  }
}

function showHubImagePreview(imageUrl, filename) {
  // Show a small preview above the input
  const inputArea = document.querySelector('.chat-input-area');
  if (!inputArea) return;
  
  // Remove any existing preview
  const existingPreview = inputArea.querySelector('.hub-image-preview');
  if (existingPreview) {
    existingPreview.remove();
  }
  
  // Create preview
  const preview = document.createElement('div');
  preview.className = 'hub-image-preview';
  preview.innerHTML = `
    <div class="hub-preview-content">
      <img src="${imageUrl}" alt="${filename}">
      <button type="button" class="hub-preview-remove" onclick="removeHubImagePreview()">
        <i data-lucide="x" style="width: 14px; height: 14px;"></i>
      </button>
    </div>
    <div class="hub-preview-info">
      <span class="hub-preview-name">${filename}</span>
      <span class="hub-preview-hint">Image will be sent with your message</span>
    </div>
  `;
  
  // Insert before the form
  const form = inputArea.querySelector('form');
  if (form) {
    inputArea.insertBefore(preview, form);
  }
  
  // Initialize Lucide icons
  if (typeof lucide !== 'undefined') {
    lucide.createIcons();
  }
}

function removeHubImagePreview() {
  const preview = document.querySelector('.hub-image-preview');
  if (!preview) return;
  
  // Remove the image markdown from textarea
  const messageInput = document.getElementById('message-input');
  if (messageInput) {
    const value = messageInput.value;
    // Remove ![...](url) pattern
    messageInput.value = value.replace(/!\[([^\]]*)\]\([^)]+\)\n?/g, '');
    
    // Auto-resize
    messageInput.style.height = 'auto';
    messageInput.style.height = messageInput.scrollHeight + 'px';
  }
  
  preview.remove();
  console.log('🗑️ Image preview removed');
}

// Export functions
window.removeHubImagePreview = removeHubImagePreview;

console.log('✅ Hub Screenshot Paste module loaded');

