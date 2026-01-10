# frozen_string_literal: true

module Modules
  # EnhancedFormRenderer - Renders rich forms with sections, tabs, and actions
  #
  # Features:
  # - Multiple layouts: single_column, two_column, tabbed, wizard
  # - Field sections with collapsible panels
  # - Conditional field visibility
  # - Action buttons with dynamic visibility
  # - AI assistance integration
  # - Rich field components
  #
  class EnhancedFormRenderer
    attr_reader :app_module, :canvas, :record, :user, :entity, :context
    
    def initialize(app_module:, canvas:, record: nil, user: nil, entity: nil, context: :edit)
      @app_module = app_module
      @canvas = canvas
      @record = record
      @user = user
      @entity = entity
      @context = context  # :create, :edit, :view
    end
    
    def render
      layout = canvas.layout || 'single_column'
      
      case layout
      when 'tabbed'
        render_tabbed_form
      when 'wizard'
        render_wizard_form
      when 'two_column'
        render_two_column_form
      else
        render_single_column_form
      end
    end
    
    private
    
    # =========================================
    # LAYOUT RENDERERS
    # =========================================
    
    def render_single_column_form
      sections = build_sections
      actions = toolbar_actions
      
      <<~HTML
        <div class="module-form-canvas p-4" data-module="#{app_module.slug}" data-controller="module-form">
          #{render_form_header}
          
          <form id="module-record-form" class="module-form" data-record-id="#{record&.id}">
            #{render_sections_single_column(sections)}
            
            <div class="form-footer mt-4 pt-3 border-top d-flex justify-content-between">
              #{render_form_actions(actions)}
            </div>
          </form>
        </div>
        
        #{render_form_scripts}
      HTML
    end
    
    def render_two_column_form
      sections = build_sections
      main_sections = sections.select { |s| s[:position] != 'sidebar' }
      sidebar_sections = sections.select { |s| s[:position] == 'sidebar' }
      
      <<~HTML
        <div class="module-form-canvas p-4" data-module="#{app_module.slug}" data-controller="module-form">
          #{render_form_header}
          
          <form id="module-record-form" class="module-form" data-record-id="#{record&.id}">
            <div class="row">
              <div class="col-md-8">
                #{render_sections_single_column(main_sections)}
              </div>
              <div class="col-md-4">
                #{render_sidebar_sections(sidebar_sections)}
              </div>
            </div>
            
            <div class="form-footer mt-4 pt-3 border-top d-flex justify-content-between">
              #{render_form_actions(toolbar_actions)}
            </div>
          </form>
        </div>
        
        #{render_form_scripts}
      HTML
    end
    
    def render_tabbed_form
      tabs = build_tabs
      
      <<~HTML
        <div class="module-form-canvas p-4" data-module="#{app_module.slug}" data-controller="module-form">
          #{render_form_header}
          
          <form id="module-record-form" class="module-form" data-record-id="#{record&.id}">
            <ul class="nav nav-tabs mb-3" role="tablist">
              #{render_tab_headers(tabs)}
            </ul>
            
            <div class="tab-content">
              #{render_tab_panes(tabs)}
            </div>
            
            <div class="form-footer mt-4 pt-3 border-top d-flex justify-content-between">
              #{render_form_actions(toolbar_actions)}
            </div>
          </form>
        </div>
        
        #{render_form_scripts}
      HTML
    end
    
    def render_wizard_form
      steps = build_wizard_steps
      
      <<~HTML
        <div class="module-form-canvas p-4" data-module="#{app_module.slug}" data-controller="module-form-wizard">
          #{render_form_header}
          
          <form id="module-record-form" class="module-form wizard-form" data-record-id="#{record&.id}">
            #{render_wizard_progress(steps)}
            
            <div class="wizard-steps">
              #{render_wizard_steps(steps)}
            </div>
            
            <div class="wizard-footer mt-4 pt-3 border-top d-flex justify-content-between">
              #{render_wizard_navigation}
            </div>
          </form>
        </div>
        
        #{render_wizard_scripts}
      HTML
    end
    
    # =========================================
    # COMPONENT RENDERERS
    # =========================================
    
    def render_form_header
      icon = app_module.icon || 'file-text'
      title = record ? "Edit #{app_module.name.singularize}" : "New #{app_module.name.singularize}"
      
      <<~HTML
        <div class="d-flex justify-content-between align-items-center mb-4">
          <h3>
            <i data-lucide="#{record ? 'edit' : 'plus'}"></i> 
            #{title}
          </h3>
          <button type="button" class="btn btn-outline-secondary" onclick="navigateToList()">
            <i data-lucide="arrow-left"></i> Back to List
          </button>
        </div>
      HTML
    end
    
    def render_sections_single_column(sections)
      sections.map do |section|
        render_section(section)
      end.join("\n")
    end
    
    def render_sidebar_sections(sections)
      sections.map do |section|
        render_section(section, sidebar: true)
      end.join("\n")
    end
    
    def render_section(section, sidebar: false)
      card_class = sidebar ? 'mb-3' : 'mb-4'
      collapsed = section[:collapsed] ? 'collapsed' : ''
      show = section[:collapsed] ? '' : 'show'
      
      visible_fields = section[:fields].select { |f| field_visible?(f) }
      return '' if visible_fields.empty?
      
      <<~HTML
        <div class="card #{card_class}" data-section="#{section[:name]}" #{section_visibility_attrs(section)}>
          <div class="card-header d-flex justify-content-between align-items-center #{collapsed}" 
               data-bs-toggle="collapse" 
               data-bs-target="#section-#{section[:name]}"
               role="button">
            <span>
              <i data-lucide="#{section[:icon] || 'file-text'}" style="width: 16px; height: 16px;"></i>
              #{section[:label]}
            </span>
            <i data-lucide="chevron-down" style="width: 16px; height: 16px;"></i>
          </div>
          <div class="collapse #{show}" id="section-#{section[:name]}">
            <div class="card-body">
              #{render_fields(visible_fields)}
            </div>
          </div>
        </div>
      HTML
    end
    
    def render_tab_headers(tabs)
      tabs.map.with_index do |tab, i|
        active = i == 0 ? 'active' : ''
        visibility_attrs = tab_visibility_attrs(tab)
        
        <<~HTML
          <li class="nav-item" role="presentation" #{visibility_attrs}>
            <button class="nav-link #{active}" 
                    id="tab-#{tab[:name]}-btn"
                    data-bs-toggle="tab" 
                    data-bs-target="#tab-#{tab[:name]}" 
                    type="button" 
                    role="tab">
              <i data-lucide="#{tab[:icon] || 'file-text'}" style="width: 16px; height: 16px;"></i>
              #{tab[:label]}
            </button>
          </li>
        HTML
      end.join("\n")
    end
    
    def render_tab_panes(tabs)
      tabs.map.with_index do |tab, i|
        active = i == 0 ? 'show active' : ''
        
        <<~HTML
          <div class="tab-pane fade #{active}" 
               id="tab-#{tab[:name]}" 
               role="tabpanel">
            #{render_tab_content(tab)}
          </div>
        HTML
      end.join("\n")
    end
    
    def render_tab_content(tab)
      if tab[:sections].present?
        tab[:sections].map do |section_name|
          section = build_section(section_name)
          render_section(section) if section
        end.compact.join("\n")
      elsif tab[:fields].present?
        render_fields(tab[:fields])
      else
        '<p class="text-muted">No content for this tab.</p>'
      end
    end
    
    def render_fields(fields)
      fields.map do |field|
        render_field(field)
      end.join("\n")
    end
    
    def render_field(field)
      field_name = field['name'] || field[:name]
      field_type = field['type'] || field['field_type'] || field[:type] || 'string'
      label = (field['label'] || field[:label] || field_name).to_s.titleize
      required = field['required'] || field[:required]
      help_text = field['help'] || field['help_text'] || field[:help]
      current_value = record.try(field_name) if record
      visibility_attrs = field_visibility_attrs(field)
      
      # Check for field-level actions
      field_actions = app_module.field_actions(field_name)
      
      <<~HTML
        <div class="mb-3" data-field="#{field_name}" #{visibility_attrs}>
          <label class="form-label#{required ? ' required' : ''}">
            #{label}
            #{render_field_actions(field_actions) if field_actions.any?}
          </label>
          #{render_field_input(field, current_value)}
          #{help_text.present? ? "<small class='form-text text-muted'>#{help_text}</small>" : ''}
        </div>
      HTML
    end
    
    def render_field_input(field, current_value)
      field_name = field['name'] || field[:name]
      field_type = field['type'] || field['field_type'] || field[:type] || 'string'
      required = field['required'] || field[:required] ? 'required' : ''
      readonly = field['visibility'] == 'read_only' ? 'readonly disabled' : ''
      ui_component = field['ui_component'] || field[:ui_component]
      options = field['options'] || field[:options] || []
      
      value = format_value_for_input(current_value, field_type)
      escaped_value = ERB::Util.html_escape(value || '')
      
      case ui_component&.to_s || field_type.to_s.downcase
      when 'rich_text_editor'
        # Use Trix editor for rich text
        editor_id = "trix_#{field_name}_#{SecureRandom.hex(4)}"
        <<~HTML
          <div class="rich-text-editor-wrapper">
            <input type="hidden" id="#{editor_id}_input" name="#{field_name}" value="#{escaped_value}">
            <trix-editor input="#{editor_id}_input" class="trix-content" #{readonly}></trix-editor>
          </div>
        HTML
      when 'text', 'textarea'
        <<~HTML
          <textarea name="#{field_name}" class="form-control" rows="3" #{required} #{readonly}>#{escaped_value}</textarea>
        HTML
      when 'select'
        options_html = options.map do |opt|
          opt_value = opt.is_a?(Hash) ? opt['value'] : opt
          opt_label = opt.is_a?(Hash) ? opt['label'] : opt.to_s.titleize
          selected = current_value.to_s == opt_value.to_s ? 'selected' : ''
          "<option value='#{opt_value}' #{selected}>#{opt_label}</option>"
        end.join("\n")
        
        <<~HTML
          <select name="#{field_name}" class="form-select" #{required} #{readonly}>
            <option value="">Select...</option>
            #{options_html}
          </select>
        HTML
      when 'multi_select'
        options_html = options.map do |opt|
          opt_value = opt.is_a?(Hash) ? opt['value'] : opt
          opt_label = opt.is_a?(Hash) ? opt['label'] : opt.to_s.titleize
          checked = Array(current_value).include?(opt_value) ? 'checked' : ''
          <<~HTML
            <div class="form-check form-check-inline">
              <input type="checkbox" name="#{field_name}[]" value="#{opt_value}" 
                     class="form-check-input" id="#{field_name}_#{opt_value}" #{checked}>
              <label class="form-check-label" for="#{field_name}_#{opt_value}">#{opt_label}</label>
            </div>
          HTML
        end.join("\n")
        
        "<div class='multi-select-group'>#{options_html}</div>"
      when 'boolean', 'checkbox'
        checked = current_value ? 'checked' : ''
        <<~HTML
          <div class="form-check">
            <input type="checkbox" name="#{field_name}" class="form-check-input" id="#{field_name}" #{checked} #{readonly}>
          </div>
        HTML
      when 'date'
        <<~HTML
          <input type="date" name="#{field_name}" class="form-control" value="#{escaped_value}" #{required} #{readonly}>
        HTML
      when 'datetime', 'datetime_picker'
        <<~HTML
          <input type="datetime-local" name="#{field_name}" class="form-control" value="#{escaped_value}" #{required} #{readonly}>
        HTML
      when 'integer', 'number'
        <<~HTML
          <input type="number" name="#{field_name}" class="form-control" value="#{escaped_value}" #{required} #{readonly}>
        HTML
      when 'decimal', 'float'
        <<~HTML
          <input type="number" step="0.01" name="#{field_name}" class="form-control" value="#{escaped_value}" #{required} #{readonly}>
        HTML
      when 'json', 'object', 'array'
        json_value = current_value.is_a?(Hash) || current_value.is_a?(Array) ? JSON.pretty_generate(current_value) : current_value
        <<~HTML
          <textarea name="#{field_name}" class="form-control font-monospace" rows="4" #{required} #{readonly}>#{ERB::Util.html_escape(json_value || '')}</textarea>
        HTML
      when 'media_gallery'
        <<~HTML
          <div class="media-gallery-input" data-field="#{field_name}">
            <div class="media-preview mb-2" id="#{field_name}-preview">
              #{render_media_preview(current_value)}
            </div>
            <input type="file" name="#{field_name}[]" class="form-control" multiple accept="image/*,video/*">
            <input type="hidden" name="#{field_name}_existing" value="#{ERB::Util.html_escape((current_value || []).to_json)}">
          </div>
        HTML
      when 'user_select'
        <<~HTML
          <input type="text" name="#{field_name}" class="form-control user-select" 
                 value="#{escaped_value}" #{required} #{readonly}
                 placeholder="Enter user name or email">
        HTML
      else
        <<~HTML
          <input type="text" name="#{field_name}" class="form-control" value="#{escaped_value}" #{required} #{readonly}>
        HTML
      end
    end
    
    def render_field_actions(actions)
      return '' if actions.blank?
      
      actions.map do |action|
        <<~HTML
          <button type="button" class="btn btn-sm btn-outline-primary ms-2 field-action" 
                  data-action-id="#{action.id}" 
                  onclick="executeFieldAction(#{action.id})">
            <i data-lucide="#{action.icon}" style="width: 12px; height: 12px;"></i>
            #{action.name}
          </button>
        HTML
      end.join
    end
    
    def render_form_actions(actions)
      left_actions = []
      right_actions = []
      
      # Primary save button always on right
      right_actions << <<~HTML
        <button type="button" class="btn btn-primary" onclick="saveModuleRecord()">
          <i data-lucide="save"></i> #{record ? 'Save Changes' : 'Create'}
        </button>
      HTML
      
      # Cancel button
      right_actions << <<~HTML
        <button type="button" class="btn btn-outline-secondary ms-2" onclick="navigateToList()">
          Cancel
        </button>
      HTML
      
      # Custom actions
      actions.each do |action|
        next unless action.visible_for?(record, user)
        
        btn = <<~HTML
          <button type="button" class="btn btn-#{action.style} ms-2" 
                  onclick="executeAction(#{action.id})">
            <i data-lucide="#{action.icon}"></i> #{action.name}
          </button>
        HTML
        
        left_actions << btn
      end
      
      <<~HTML
        <div class="action-group-left">
          #{left_actions.join("\n")}
        </div>
        <div class="action-group-right">
          #{right_actions.join("\n")}
        </div>
      HTML
    end
    
    def render_media_preview(value)
      return '' if value.blank?
      
      items = Array(value)
      items.first(4).map do |item|
        url = item.is_a?(Hash) ? item['url'] : item
        <<~HTML
          <img src="#{url}" class="media-preview-item" style="max-height: 60px; margin-right: 4px;">
        HTML
      end.join
    end
    
    # =========================================
    # SCRIPTS
    # =========================================
    
    def render_form_scripts
      <<~HTML
        <script>
          // Form utilities - DIRECT API CALLS, no chat messages!
          const MODULE_SLUG = '#{app_module.slug}';
          const MODEL_NAME = '#{app_module.slug.classify}';
          
          function navigateToList() {
            // Load list canvas directly via AJAX
            const canvasName = 'module_' + MODULE_SLUG + '_list';
            
            fetch('/scout/load_canvas', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
              },
              body: JSON.stringify({ canvas_type: canvasName, canvas_data: {} })
            })
            .then(response => response.json())
            .then(data => {
              if (data.success && data.canvas) {
                const canvasContainer = document.getElementById('canvas-content') || 
                                        document.querySelector('.canvas-body') ||
                                        document.querySelector('[data-scout-target="canvasContent"]');
                if (canvasContainer) {
                  canvasContainer.innerHTML = data.canvas.content;
                  if (window.lucide) lucide.createIcons();
                }
              }
            })
            .catch(err => console.error('Error navigating to list:', err));
          }
          
          async function saveModuleRecord() {
            const form = document.getElementById('module-record-form');
            const formData = new FormData(form);
            const data = {};
            
            formData.forEach((value, key) => {
              // Handle array fields
              if (key.endsWith('[]')) {
                const arrayKey = key.slice(0, -2);
                data[arrayKey] = data[arrayKey] || [];
                data[arrayKey].push(value);
              } else if (!key.endsWith('_existing')) {
                data[key] = value;
              }
            });
            
            const recordId = form.dataset.recordId;
            const method = recordId ? 'PATCH' : 'POST';
            const url = recordId 
              ? '/api/modules/' + MODULE_SLUG + '/models/' + MODEL_NAME + '/' + recordId
              : '/api/modules/' + MODULE_SLUG + '/models/' + MODEL_NAME;
            
            // Show saving state
            const saveBtn = document.querySelector('button[onclick="saveModuleRecord()"]');
            if (saveBtn) {
              saveBtn.disabled = true;
              saveBtn.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Saving...';
            }
            
            try {
              const response = await fetch(url, {
                method: method,
                headers: {
                  'Content-Type': 'application/json',
                  'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                },
                body: JSON.stringify(data)
              });
              
              const result = await response.json();
              
              if (response.ok && result.success) {
                showFormToast('success', recordId ? 'Record updated!' : 'Record created!');
                // Navigate back to list after short delay
                setTimeout(() => navigateToList(), 1000);
              } else {
                showFormToast('error', result.message || 'Save failed');
              }
            } catch (err) {
              console.error('Save error:', err);
              showFormToast('error', 'Failed to save. Please try again.');
            } finally {
              if (saveBtn) {
                saveBtn.disabled = false;
                saveBtn.innerHTML = '<i data-lucide="save"></i> ' + (recordId ? 'Save Changes' : 'Create');
                if (window.lucide) lucide.createIcons();
              }
            }
          }
          
          function showFormToast(type, message) {
            const toast = document.createElement('div');
            toast.className = 'alert alert-' + (type === 'error' ? 'danger' : 'success') + ' position-fixed';
            toast.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 250px;';
            toast.innerHTML = '<div class="d-flex align-items-center"><i data-lucide="' + (type === 'error' ? 'alert-circle' : 'check-circle') + '"></i><span class="ms-2">' + message + '</span></div>';
            document.body.appendChild(toast);
            if (window.lucide) lucide.createIcons();
            setTimeout(() => toast.remove(), 4000);
          }
          
          function executeAction(actionId) {
            // TODO: Implement direct action execution via API
            console.log('Execute action:', actionId);
            showFormToast('info', 'Action execution coming soon!');
          }
          
          function executeFieldAction(actionId) {
            // TODO: Implement field action execution via API
            console.log('Execute field action:', actionId);
            showFormToast('info', 'Field action coming soon!');
          }
          
          // Conditional field visibility
          function updateFieldVisibility() {
            const form = document.getElementById('module-record-form');
            if (!form) return;
            
            document.querySelectorAll('[data-show-when]').forEach(el => {
              const condition = JSON.parse(el.dataset.showWhen || '{}');
              const field = condition.field;
              const input = form.querySelector('[name="' + field + '"]');
              
              if (!input) return;
              
              const value = input.value;
              let visible = true;
              
              if (condition.equals) {
                visible = value === condition.equals;
              } else if (condition.not_equals) {
                visible = value !== condition.not_equals;
              } else if (condition.in) {
                visible = condition.in.includes(value);
              }
              
              el.style.display = visible ? '' : 'none';
            });
          }
          
          // Initialize
          document.addEventListener('DOMContentLoaded', function() {
            updateFieldVisibility();
            
            // Watch for field changes
            document.querySelectorAll('#module-record-form select, #module-record-form input').forEach(input => {
              input.addEventListener('change', updateFieldVisibility);
            });
          });
          
          if (window.lucide) lucide.createIcons();
        </script>
      HTML
    end
    
    def render_wizard_scripts
      <<~HTML
        <script>
          let currentStep = 0;
          const totalSteps = #{build_wizard_steps.length};
          
          function showStep(step) {
            document.querySelectorAll('.wizard-step').forEach((el, i) => {
              el.style.display = i === step ? 'block' : 'none';
            });
            
            document.querySelectorAll('.wizard-progress-step').forEach((el, i) => {
              el.classList.toggle('active', i <= step);
              el.classList.toggle('current', i === step);
            });
            
            document.getElementById('wizard-prev').disabled = step === 0;
            document.getElementById('wizard-next').style.display = step === totalSteps - 1 ? 'none' : 'inline-block';
            document.getElementById('wizard-submit').style.display = step === totalSteps - 1 ? 'inline-block' : 'none';
            
            currentStep = step;
          }
          
          function nextStep() {
            if (currentStep < totalSteps - 1) showStep(currentStep + 1);
          }
          
          function prevStep() {
            if (currentStep > 0) showStep(currentStep - 1);
          }
          
          document.addEventListener('DOMContentLoaded', function() {
            showStep(0);
          });
          
          #{render_form_scripts}
        </script>
      HTML
    end
    
    # =========================================
    # BUILDERS
    # =========================================
    
    def build_sections
      if canvas.sections.present?
        canvas.sections.map { |s| symbolize_section(s) }
      else
        fields_by_section = app_module.fields_by_section
        app_module.sections_config.map do |section_config|
          section_name = section_config['name']
          section_fields = fields_by_section[section_name] || []
          
          {
            name: section_name,
            label: section_config['label'] || section_name.titleize,
            icon: section_config['icon'] || 'file-text',
            fields: section_fields,
            collapsed: section_config['collapsed'] || false,
            show_when: section_config['show_when']
          }
        end.select { |s| s[:fields].any? }
      end
    end
    
    def build_tabs
      if canvas.tabs.present?
        canvas.tabs.map { |t| symbolize_section(t) }
      else
        # Default: one tab per section
        build_sections.map do |section|
          {
            name: section[:name],
            label: section[:label],
            icon: section[:icon],
            sections: [section[:name]],
            show_when: section[:show_when]
          }
        end
      end
    end
    
    def build_wizard_steps
      build_tabs.map.with_index do |tab, i|
        {
          step: i + 1,
          name: tab[:name],
          label: tab[:label],
          icon: tab[:icon],
          sections: tab[:sections]
        }
      end
    end
    
    def build_section(section_name)
      all_sections = build_sections
      all_sections.find { |s| s[:name] == section_name }
    end
    
    def symbolize_section(section)
      {
        name: section['name'] || section[:name],
        label: section['label'] || section[:label] || section['name']&.titleize,
        icon: section['icon'] || section[:icon] || 'file-text',
        fields: section['fields'] || section[:fields] || [],
        sections: section['sections'] || section[:sections],
        collapsed: section['collapsed'] || section[:collapsed],
        show_when: section['show_when'] || section[:show_when],
        position: section['position'] || section[:position]
      }
    end
    
    def toolbar_actions
      app_module.toolbar_actions(record, user)
    end
    
    # =========================================
    # VISIBILITY HELPERS
    # =========================================
    
    def field_visible?(field)
      visibility = field['visibility'] || field[:visibility] || 'always'
      
      case visibility.to_s
      when 'always'
        true
      when 'create_only'
        context == :create
      when 'edit_only'
        context == :edit
      when 'read_only'
        context == :view || context == :edit
      when 'system', 'never'
        false
      else
        # Check show_when condition
        show_when = field['show_when'] || field[:show_when]
        return true if show_when.blank? || record.blank?
        
        app_module.condition_met?(show_when, record)
      end
    end
    
    def field_visibility_attrs(field)
      show_when = field['show_when'] || field[:show_when]
      return '' if show_when.blank?
      
      "data-show-when='#{show_when.to_json}'"
    end
    
    def section_visibility_attrs(section)
      show_when = section[:show_when]
      return '' if show_when.blank?
      
      "data-show-when='#{show_when.to_json}'"
    end
    
    def tab_visibility_attrs(tab)
      show_when = tab[:show_when]
      return '' if show_when.blank?
      
      "data-show-when='#{show_when.to_json}'"
    end
    
    def format_value_for_input(value, field_type)
      return '' if value.nil?
      
      case field_type.to_s.downcase
      when 'date'
        value.respond_to?(:strftime) ? value.strftime('%Y-%m-%d') : value.to_s
      when 'datetime'
        value.respond_to?(:strftime) ? value.strftime('%Y-%m-%dT%H:%M') : value.to_s
      when 'json', 'array', 'object'
        value.is_a?(String) ? value : value.to_json
      else
        value.to_s
      end
    end
    
    # Wizard-specific renderers
    def render_wizard_progress(steps)
      steps_html = steps.map do |step|
        <<~HTML
          <div class="wizard-progress-step" data-step="#{step[:step]}">
            <div class="step-number">#{step[:step]}</div>
            <div class="step-label">#{step[:label]}</div>
          </div>
        HTML
      end.join('<div class="wizard-progress-connector"></div>')
      
      "<div class='wizard-progress mb-4 d-flex justify-content-between'>#{steps_html}</div>"
    end
    
    def render_wizard_steps(steps)
      steps.map do |step|
        <<~HTML
          <div class="wizard-step" data-step="#{step[:step]}" style="display: none;">
            #{render_tab_content(step)}
          </div>
        HTML
      end.join("\n")
    end
    
    def render_wizard_navigation
      <<~HTML
        <button type="button" id="wizard-prev" class="btn btn-outline-secondary" onclick="prevStep()">
          <i data-lucide="arrow-left"></i> Previous
        </button>
        <button type="button" id="wizard-next" class="btn btn-primary" onclick="nextStep()">
          Next <i data-lucide="arrow-right"></i>
        </button>
        <button type="button" id="wizard-submit" class="btn btn-success" onclick="saveModuleRecord()" style="display: none;">
          <i data-lucide="check"></i> Submit
        </button>
      HTML
    end
  end
end



