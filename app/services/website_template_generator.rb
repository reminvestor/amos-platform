# frozen_string_literal: true

# WebsiteTemplateGenerator
#
# Generates Liquid templates for website pages based on module schema
# and page type. These templates render module data using proper Liquid
# syntax ({{ variable }}, {% for %}, {% if %}) with Bootstrap styling.
#
# Usage:
#   generator = WebsiteTemplateGenerator.new
#   html = generator.generate(
#     page_type: 'list',
#     module_name: 'Products',
#     module_slug: 'products',
#     fields: [...],
#     options: {}
#   )
#
class WebsiteTemplateGenerator
  # Generate a Liquid template for a website page
  #
  # @param page_type [String] Type of page: homepage, list, detail, form, landing
  # @param module_name [String] Human-readable module name
  # @param module_slug [String] Module slug for API paths and variable names
  # @param fields [Array<Hash>] Field definitions from the module spec
  # @param options [Hash] Additional options (theme, features, etc.)
  # @return [String] Liquid template HTML
  def generate(page_type:, module_name:, module_slug:, fields: [], options: {})
    case page_type.to_s
    when 'homepage'
      generate_homepage(module_name, module_slug, fields, options)
    when 'list'
      generate_list_page(module_name, module_slug, fields, options)
    when 'detail'
      generate_detail_page(module_name, module_slug, fields, options)
    when 'form'
      generate_form_page(module_name, module_slug, fields, options)
    when 'landing'
      generate_landing_page(module_name, module_slug, fields, options)
    else
      generate_content_page(module_name, module_slug, options)
    end
  end

  private

  def generate_homepage(module_name, module_slug, fields, options)
    collection = module_slug.pluralize
    title_field = find_title_field(fields)
    desc_field = find_description_field(fields)
    status_field = find_status_field(fields)

    <<~LIQUID
      <section class="hero bg-primary text-white py-5">
        <div class="container text-center">
          <h1 class="display-4 fw-bold">{{ site_name | default: "#{module_name}" }}</h1>
          <p class="lead">{{ description | default: "Welcome to our #{module_name.downcase} portal" }}</p>
          {% if record_count and record_count > 0 %}
            <p class="mb-4"><strong>{{ record_count }}</strong> #{module_name.downcase} available</p>
          {% endif %}
          <div class="row justify-content-center mt-4">
            <div class="col-md-6">
              <form action="/#{module_slug}" method="get" class="input-group input-group-lg">
                <input type="search" name="search" class="form-control" placeholder="Search #{module_name.downcase}...">
                <button class="btn btn-light" type="submit">Search</button>
              </form>
            </div>
          </div>
        </div>
      </section>

      <section class="py-5">
        <div class="container">
          <h2 class="mb-4">Recent #{module_name}</h2>
          <div class="row">
            {% for item in #{collection} limit:6 %}
              <div class="col-md-4 mb-4">
                <div class="card h-100 shadow-sm">
                  <div class="card-body">
                    <h5 class="card-title">{{ item.#{title_field} }}</h5>
                    #{desc_field ? "<p class=\"card-text text-muted\">{{ item.#{desc_field} | truncate_words: 20 }}</p>" : ''}
                    #{status_field ? "<p>{{ item.#{status_field} | status_badge }}</p>" : ''}
                    <a href="/#{module_slug}/{{ item.id }}" class="btn btn-outline-primary btn-sm">View Details</a>
                  </div>
                  <div class="card-footer text-muted small">
                    {{ item.created_at | format_date }}
                  </div>
                </div>
              </div>
            {% endfor %}
          </div>
          {% if record_count and record_count > 6 %}
            <div class="text-center mt-4">
              <a href="/browse" class="btn btn-primary">View All #{module_name}</a>
            </div>
          {% endif %}
        </div>
      </section>
    LIQUID
  end

  def generate_list_page(module_name, module_slug, fields, options)
    collection = module_slug.pluralize
    display_fields = fields.first(6)
    title_field = find_title_field(fields)
    status_field = find_status_field(fields)

    header_cells = display_fields.map { |f| "<th>#{field_label(f)}</th>" }.join("\n              ")
    data_cells = display_fields.map do |f|
      fname = f['name'] || f[:name]
      ftype = f['field_type'] || f['type'] || f[:type] || 'string'
      case ftype
      when 'date', 'datetime'
        "<td>{{ item.#{fname} | format_date }}</td>"
      when 'select'
        "<td>{{ item.#{fname} | status_badge }}</td>"
      when 'decimal'
        "<td>{{ item.#{fname} | currency }}</td>"
      else
        "<td>{{ item.#{fname} }}</td>"
      end
    end.join("\n              ")

    <<~LIQUID
      <section class="py-5">
        <div class="container">
          <div class="d-flex justify-content-between align-items-center mb-4">
            <h1>#{module_name}</h1>
            <span class="text-muted">{{ record_count | default: 0 }} record{{ record_count | pluralize: "", "s" }}</span>
          </div>

          {% if records.size > 0 %}
            <div class="card shadow-sm">
              <div class="table-responsive">
                <table class="table table-hover mb-0">
                  <thead class="table-light">
                    <tr>
                      #{header_cells}
                      <th class="text-end">Details</th>
                    </tr>
                  </thead>
                  <tbody>
                    {% for item in #{collection} %}
                      <tr>
                        #{data_cells}
                        <td class="text-end">
                          <a href="/#{module_slug}/{{ item.id }}" class="btn btn-sm btn-outline-primary">View</a>
                        </td>
                      </tr>
                    {% endfor %}
                  </tbody>
                </table>
              </div>
            </div>
          {% else %}
            <div class="text-center py-5">
              <p class="text-muted lead">No #{module_name.downcase} found.</p>
            </div>
          {% endif %}
        </div>
      </section>
    LIQUID
  end

  def generate_detail_page(module_name, module_slug, fields, options)
    singular = module_name.singularize
    title_field = find_title_field(fields)
    status_field = find_status_field(fields)
    desc_field = find_description_field(fields)

    # Build field display rows
    field_rows = fields.map do |f|
      fname = f['name'] || f[:name]
      ftype = f['field_type'] || f['type'] || f[:type] || 'string'
      label = field_label(f)

      value_template = case ftype
                       when 'date', 'datetime'
                         "{{ record.#{fname} | format_date }}"
                       when 'select'
                         "{{ record.#{fname} | status_badge }}"
                       when 'text'
                         "{{ record.#{fname} | markdown }}"
                       when 'decimal'
                         "{{ record.#{fname} | currency }}"
                       when 'boolean'
                         "{% if record.#{fname} %}Yes{% else %}No{% endif %}"
                       else
                         "{{ record.#{fname} | default: \"—\" }}"
                       end

      <<~ROW
              <div class="row py-2 border-bottom">
                <div class="col-sm-3 fw-semibold text-muted">#{label}</div>
                <div class="col-sm-9">#{value_template}</div>
              </div>
      ROW
    end.join

    <<~LIQUID
      <section class="py-5">
        <div class="container">
          {% if record %}
            <nav aria-label="breadcrumb" class="mb-3">
              <ol class="breadcrumb">
                <li class="breadcrumb-item"><a href="/">Home</a></li>
                <li class="breadcrumb-item"><a href="/browse">#{module_name}</a></li>
                <li class="breadcrumb-item active">{{ record.#{title_field} }}</li>
              </ol>
            </nav>

            <div class="d-flex justify-content-between align-items-start mb-4">
              <div>
                <h1>{{ record.#{title_field} }}</h1>
                #{status_field ? "<p>{{ record.#{status_field} | status_badge }}</p>" : ''}
              </div>
              <a href="/browse" class="btn btn-outline-secondary">Back to List</a>
            </div>

            #{desc_field ? "<div class=\"lead mb-4\">{{ record.#{desc_field} }}</div>" : ''}

            <div class="card shadow-sm">
              <div class="card-body">
      #{field_rows}
                <div class="row py-2">
                  <div class="col-sm-3 fw-semibold text-muted">Created</div>
                  <div class="col-sm-9">{{ record.created_at | format_date }}</div>
                </div>
              </div>
            </div>
          {% else %}
            <div class="text-center py-5">
              <h2>#{singular} Not Found</h2>
              <p class="text-muted">The requested #{singular.downcase} could not be found.</p>
              <a href="/browse" class="btn btn-primary">Browse #{module_name}</a>
            </div>
          {% endif %}
        </div>
      </section>
    LIQUID
  end

  def generate_form_page(module_name, module_slug, fields, options)
    singular = module_name.singularize
    api_path = "/api/modules/#{module_slug}/models/#{module_slug.classify}"

    form_fields = fields.map do |f|
      fname = f['name'] || f[:name]
      ftype = f['field_type'] || f['type'] || f[:type] || 'string'
      label = field_label(f)
      required = f['required'] || f[:required]
      field_options = f['options'] || f[:options]
      req_attr = required ? 'required' : ''

      case ftype
      when 'text'
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><textarea name='#{fname}' class='form-control' rows='3' #{req_attr}></textarea></div>"
      when 'select'
        opts = (field_options || []).map { |o| "<option value='#{o}'>#{o.to_s.titleize}</option>" }.join
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><select name='#{fname}' class='form-select' #{req_attr}><option value=''>Select...</option>#{opts}</select></div>"
      when 'boolean'
        "<div class='mb-3 form-check'><input type='checkbox' name='#{fname}' class='form-check-input' id='field-#{fname}'><label class='form-check-label' for='field-#{fname}'>#{label}</label></div>"
      when 'date'
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><input type='date' name='#{fname}' class='form-control' #{req_attr}></div>"
      when 'integer', 'decimal'
        step = ftype == 'decimal' ? " step='0.01'" : ''
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><input type='number'#{step} name='#{fname}' class='form-control' #{req_attr}></div>"
      else
        "<div class='mb-3'><label class='form-label fw-semibold'>#{label}#{required ? ' *' : ''}</label><input type='text' name='#{fname}' class='form-control' #{req_attr}></div>"
      end
    end.join("\n          ")

    <<~LIQUID
      <section class="py-5">
        <div class="container">
          <div class="row justify-content-center">
            <div class="col-md-8">
              <h1 class="mb-4">Submit #{singular}</h1>
              <div class="card shadow-sm">
                <div class="card-body">
                  <form id="submission-form">
                    #{form_fields}
                    <div class="d-flex gap-2 mt-4 pt-3 border-top">
                      <button type="submit" class="btn btn-primary">Submit</button>
                      <button type="reset" class="btn btn-outline-secondary">Reset</button>
                    </div>
                  </form>
                  <div id="form-message" class="mt-3" style="display:none"></div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
      <script>
        document.getElementById('submission-form')?.addEventListener('submit', async (e) => {
          e.preventDefault();
          const form = e.target;
          const data = {};
          new FormData(form).forEach((v, k) => { if (v !== '') data[k] = v; });
          const msgEl = document.getElementById('form-message');
          try {
            const resp = await fetch('#{api_path}', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content },
              body: JSON.stringify(data)
            });
            if (resp.ok) {
              msgEl.className = 'mt-3 alert alert-success';
              msgEl.textContent = 'Submitted successfully!';
              msgEl.style.display = 'block';
              form.reset();
            } else {
              const err = await resp.json();
              msgEl.className = 'mt-3 alert alert-danger';
              msgEl.textContent = 'Error: ' + (err.error || 'Submission failed');
              msgEl.style.display = 'block';
            }
          } catch(err) {
            msgEl.className = 'mt-3 alert alert-danger';
            msgEl.textContent = 'Error: ' + err.message;
            msgEl.style.display = 'block';
          }
        });
      </script>
    LIQUID
  end

  def generate_landing_page(module_name, module_slug, fields, options)
    <<~LIQUID
      <section class="hero bg-gradient py-5" style="background: linear-gradient(135deg, var(--primary-color, #0d6efd) 0%, #0a58ca 100%);">
        <div class="container text-center text-white">
          <h1 class="display-3 fw-bold">{{ title | default: "#{module_name}" }}</h1>
          <p class="lead mb-4">{{ description | default: "Discover everything about #{module_name.downcase}" }}</p>
          <a href="/browse" class="btn btn-light btn-lg">Browse #{module_name}</a>
        </div>
      </section>
      <section class="py-5">
        <div class="container">
          <div class="row text-center">
            <div class="col-md-4 mb-4">
              <div class="p-4">
                <h4>Browse</h4>
                <p class="text-muted">Explore our full collection of #{module_name.downcase}.</p>
                <a href="/browse" class="btn btn-outline-primary">View All</a>
              </div>
            </div>
            <div class="col-md-4 mb-4">
              <div class="p-4">
                <h4>Search</h4>
                <p class="text-muted">Find exactly what you need quickly.</p>
                <form action="/browse" method="get" class="input-group">
                  <input type="search" name="search" class="form-control" placeholder="Search...">
                  <button class="btn btn-outline-primary" type="submit">Go</button>
                </form>
              </div>
            </div>
            <div class="col-md-4 mb-4">
              <div class="p-4">
                <h4>Contact</h4>
                <p class="text-muted">Have questions? Get in touch.</p>
                <a href="/contact" class="btn btn-outline-primary">Contact Us</a>
              </div>
            </div>
          </div>
        </div>
      </section>
    LIQUID
  end

  def generate_content_page(module_name, module_slug, options)
    <<~LIQUID
      <section class="py-5">
        <div class="container">
          <h1>{{ title | default: "#{module_name}" }}</h1>
          <div class="content">
            {{ content | default: "Add your content here." }}
          </div>
        </div>
      </section>
    LIQUID
  end

  # ============================================
  # FIELD HELPERS
  # ============================================

  def find_title_field(fields)
    title = fields.find { |f| %w[title name subject heading].include?((f['name'] || f[:name]).to_s) }
    (title ? (title['name'] || title[:name]) : 'name').to_s
  end

  def find_description_field(fields)
    desc = fields.find { |f| %w[description summary body content].include?((f['name'] || f[:name]).to_s) }
    desc ? (desc['name'] || desc[:name]).to_s : nil
  end

  def find_status_field(fields)
    status = fields.find { |f| (f['name'] || f[:name]).to_s == 'status' }
    status ? 'status' : nil
  end

  def field_label(field)
    (field['name'] || field[:name]).to_s.titleize
  end
end
