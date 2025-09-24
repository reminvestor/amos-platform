class ToolRegistry
  # Tool contracts with input/output schemas and metadata
  TOOLS = {
    'generate_landing_page_dsl' => {
      version: '1.0',
      description: 'Generate landing page DSL from business requirements',
      input_schema: {
        type: 'object',
        required: ['business_info'],
        properties: {
          business_info: {
            type: 'object',
            required: ['business_name'],
            properties: {
              business_name: { type: 'string', minLength: 2, maxLength: 100 },
              industry: { type: 'string', maxLength: 50 },
              target_audience: { type: 'string', maxLength: 500 },
              key_message: { type: 'string', maxLength: 500 },
              page_purpose: { type: 'string' },
              specific_details: { type: 'string' },
              call_to_action: { type: 'string' }
            }
          },
          design_preferences: {
            type: 'object',
            properties: {
              theme: { 
                type: 'string', 
                enum: ['clean', 'modern', 'bold', 'professional', 'creative'] 
              },
              primary_color: { 
                type: 'string', 
                pattern: '^#[0-9a-fA-F]{6}$' 
              },
              style_notes: { type: 'string', maxLength: 500 }
            }
          },
          stored_images: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                id: { type: 'integer' },
                url: { type: 'string' },
                title: { type: 'string' },
                description: { type: 'string' }
              }
            }
          },
          image_preferences: { type: 'object' }
        }
      },
      output_schema: {
        type: 'object',
        required: ['data'],
        properties: {
          data: {
            type: 'object',
            required: ['dsl'],
            properties: {
              dsl: { type: 'object' },
              business_info: { type: 'object' },
              design_preferences: { type: 'object' }
            }
          },
          message: { type: 'string' },
          recommendation: { type: 'string' }
        }
      },
      timeout: 30,
      retryable: true
    },
    
    'compile_landing_page_html' => {
      version: '1.0',
      description: 'Compile landing page DSL to HTML',
      input_schema: {
        type: 'object',
        required: ['dsl'],
        properties: {
          dsl: { type: 'object' },
          slug: { type: 'string', pattern: '^[a-z0-9-_]+$' }
        }
      },
      output_schema: {
        type: 'object',
        required: ['data'],
        properties: {
          data: {
            type: 'object',
            required: ['html'],
            properties: {
              html: { type: 'string', minLength: 100 },
              dsl: { type: 'object' },
              slug: { type: 'string' },
              landing_page_id: { type: 'integer' },
              landing_page: { type: 'object' }
            }
          },
          message: { type: 'string' }
        }
      },
      timeout: 10,
      retryable: false
    },
    
    'create_contact' => {
      version: '1.0',
      description: 'Create a new contact record',
      input_schema: {
        type: 'object',
        required: ['email'],
        properties: {
          email: { 
            type: 'string', 
            format: 'email',
            maxLength: 255
          },
          first_name: { type: 'string', maxLength: 100 },
          last_name: { type: 'string', maxLength: 100 },
          phone: { type: 'string', maxLength: 20 },
          company: { type: 'string', maxLength: 100 }
        }
      },
      output_schema: {
        type: 'object',
        required: ['contact_id'],
        properties: {
          contact_id: { type: 'string' },
          contact_data: { type: 'object' }
        }
      },
      timeout: 15,
      retryable: true
    },
    
    'create_campaign' => {
      version: '1.0',
      description: 'Create a new marketing campaign',
      input_schema: {
        type: 'object',
        required: ['campaign_name', 'campaign_type'],
        properties: {
          campaign_name: { type: 'string', minLength: 3, maxLength: 100 },
          campaign_type: { 
            type: 'string',
            enum: ['Email', 'Social Media', 'Mixed']
          },
          description: { type: 'string', maxLength: 500 },
          contact_group_ids: {
            type: 'array',
            items: { type: 'integer' }
          }
        }
      },
      output_schema: {
        type: 'object',
        required: ['campaign_id'],
        properties: {
          campaign_id: { type: 'string' },
          campaign_data: { type: 'object' }
        }
      },
      timeout: 20,
      retryable: true
    },
    
    'get_contact_groups' => {
      version: '1.0',
      description: 'Fetch available contact groups',
      input_schema: {
        type: 'object',
        properties: {
          user_id: { type: 'integer' },
          entity_id: { type: 'integer' }
        }
      },
      output_schema: {
        type: 'object',
        required: ['contact_groups'],
        properties: {
          contact_groups: {
            type: 'array',
            items: {
              type: 'object',
              required: ['id', 'name'],
              properties: {
                id: { type: 'integer' },
                name: { type: 'string' },
                count: { type: 'integer' }
              }
            }
          }
        }
      },
      timeout: 10,
      retryable: true
    },
    
    'send_email' => {
      version: '1.0',
      description: 'Send an email message',
      input_schema: {
        type: 'object',
        required: ['recipient', 'subject', 'body'],
        properties: {
          recipient: { type: 'string', format: 'email' },
          subject: { type: 'string', minLength: 1, maxLength: 200 },
          body: { type: 'string', minLength: 1 },
          template_id: { type: 'integer' }
        }
      },
      output_schema: {
        type: 'object',
        required: ['message_id'],
        properties: {
          message_id: { type: 'string' },
          recipient: { type: 'string' },
          subject: { type: 'string' }
        }
      },
      timeout: 15,
      retryable: true
    },
    
    'get_schema' => {
      version: '1.0',
      description: 'Get database schema information',
      input_schema: {
        type: 'object',
        properties: {
          table: { type: 'string' },
          model: { type: 'string' }
        }
      },
      output_schema: {
        type: 'object',
        required: ['schema'],
        properties: {
          schema: { type: 'string' },
          table: { type: 'string' }
        }
      },
      timeout: 5,
      retryable: false
    },
    
    'query_data' => {
      version: '1.0',
      description: 'Execute a data query',
      input_schema: {
        type: 'object',
        required: ['query'],
        properties: {
          query: { type: 'string', minLength: 1 },
          limit: { type: 'integer', minimum: 1, maximum: 1000 }
        }
      },
      output_schema: {
        type: 'object',
        required: ['results'],
        properties: {
          results: { type: 'string' },
          query: { type: 'string' },
          count: { type: 'integer' }
        }
      },
      timeout: 30,
      retryable: true
    },
    
        'process_landing_page_images' => {
          version: '1.0',
          description: 'Process and generate images for landing page based on user preferences',
          input_schema: {
            type: 'object',
            required: ['image_preferences', 'user_id', 'entity_id'],
            properties: {
              image_preferences: {
                type: 'object',
                required: ['image_preference'],
                properties: {
                  image_preference: {
                    type: 'string',
                    enum: ['ai_generate', 'upload_own', 'use_placeholders', 'skip_for_now']
                  },
                  image_style: { type: 'string' },
                  image_descriptions: { type: 'string' }
                }
              },
              business_info: { type: 'object' },
              user_id: { type: 'integer' },
              entity_id: { type: 'integer' }
            }
          },
          output_schema: {
            type: 'object',
            required: ['data'],
            properties: {
              data: {
                type: 'object',
                properties: {
                  processed_images: {
                    type: 'array',
                    items: {
                      type: 'object',
                      properties: {
                        id: { type: 'integer' },
                        url: { type: 'string' },
                        title: { type: 'string' },
                        description: { type: 'string' }
                      }
                    }
                  },
                  image_strategy: { type: 'string' }
                }
              },
              message: { type: 'string' },
              recommendation: { type: 'string' }
            }
          },
          timeout: 60,
          retryable: true
        },
        'store_uploaded_images' => {
          version: '1.0',
          description: 'Store uploaded images to S3 and create ImageAsset records for LLM context',
          input_schema: {
            type: 'object',
            required: ['image_data', 'user_id', 'entity_id'],
            properties: {
              image_data: { type: 'object' },
              user_id: { type: 'integer' },
              entity_id: { type: 'integer' }
            }
          },
          output_schema: {
            type: 'object',
            required: ['data'],
            properties: {
              data: {
                type: 'object',
                properties: {
                  stored_images: {
                    type: 'array',
                    items: {
                      type: 'object',
                      properties: {
                        id: { type: 'integer' },
                        url: { type: 'string' },
                        title: { type: 'string' },
                        description: { type: 'string' },
                        slot: { type: 'integer' }
                      }
                    }
                  },
                  design_reference: { type: 'object' }
                }
              },
              message: { type: 'string' }
            }
          },
          timeout: 30,
          retryable: true
        },
        'analyze_landing_page_request' => {
      version: '1.0',
      description: 'Analyze existing business information and landing page request',
      input_schema: {
        type: 'object',
        required: ['user_message'],
        properties: {
          user_message: { type: 'string', minLength: 1 },
          user: { 
            type: 'object',
            properties: {
              id: { type: 'integer' },
              email: { type: 'string' },
              first_name: { type: 'string' },
              last_name: { type: 'string' }
            }
          },
          entity: {
            type: 'object', 
            properties: {
              id: { type: 'integer' },
              name: { type: 'string' },
              subdomain: { type: 'string' }
            }
          }
        }
      },
      output_schema: {
        type: 'object',
        required: ['data'],
        properties: {
          data: {
            type: 'object',
            required: ['business_profile'],
            properties: {
              business_profile: { type: 'object' },
              entity: { type: 'object' },
              message_context: { type: 'object' },
              missing_info: { 
                type: 'array',
                items: { type: 'string' }
              }
            }
          },
          message: { type: 'string' },
          recommendation: { type: 'string' }
        }
      },
      timeout: 10,
      retryable: false
    },
    
    'aggregate_artifact_data' => {
      version: '1.0',
      description: 'Perform aggregation operations on artifact data (group_by, count, sum, avg)',
      input_schema: {
        type: 'object',
        required: ['artifact_id', 'operation'],
        properties: {
          artifact_id: { type: 'integer', minimum: 1 },
          operation: { 
            type: 'string', 
            enum: ['group_by_field', 'group_by_time', 'top_k', 'simple_stats'] 
          },
          field: { type: 'string' },
          time_field: { type: 'string' },
          time_bucket: { 
            type: 'string', 
            enum: ['hour', 'day', 'week', 'month', 'quarter', 'year'] 
          },
          aggregations: {
            type: 'array',
            items: {
              type: 'object',
              required: ['function', 'field'],
              properties: {
                function: { 
                  type: 'string', 
                  enum: ['count', 'sum', 'avg', 'min', 'max', 'distinct'] 
                },
                field: { type: 'string' },
                alias: { type: 'string' }
              }
            }
          },
          filters: {
            type: 'array',
            items: {
              type: 'object',
              required: ['field', 'operator', 'value'],
              properties: {
                field: { type: 'string' },
                operator: { 
                  type: 'string', 
                  enum: ['eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'contains', 'in'] 
                },
                value: {}
              }
            }
          },
          k: { type: 'integer', minimum: 1, maximum: 1000 },
          order_by: { type: 'string' },
          order_direction: { 
            type: 'string', 
            enum: ['asc', 'desc'],
            default: 'desc'
          }
        }
      },
      output_schema: {
        type: 'object',
        required: ['success'],
        properties: {
          success: { type: 'boolean' },
          data: {
            type: 'object',
            properties: {
              results: { type: 'array' },
              row_count: { type: 'integer' },
              aggregation_type: { type: 'string' },
              artifact_id: { type: 'integer' },
              visualizations: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    type: { type: 'string' },
                    config: { type: 'object' }
                  }
                }
              }
            }
          },
          error: { type: 'string' }
        }
      },
      timeout: 30,
      retryable: true
    },
    
    'fetch_next_page' => {
      version: '1.0',
      description: 'Fetch the next page of data for a paginated artifact',
      input_schema: {
        type: 'object',
        required: ['artifact_id'],
        properties: {
          artifact_id: { type: 'integer', minimum: 1 },
          cursor: { type: 'string' },
          limit: { type: 'integer', minimum: 1, maximum: 100 }
        }
      },
      output_schema: {
        type: 'object',
        required: ['success'],
        properties: {
          success: { type: 'boolean' },
          data: {
            type: 'object',
            properties: {
              artifact_id: { type: 'integer' },
              rows: { type: 'array' },
              row_count: { type: 'integer' },
              next_cursor: { type: 'string' },
              has_more: { type: 'boolean' }
            }
          },
          error: { type: 'string' }
        }
      },
      timeout: 20,
      retryable: true
    }
  }.freeze
  
  class << self
    # Get tool contract by name
    def get_contract(tool_name)
      TOOLS[tool_name.to_s]
    end
    
    # Validate inputs for a tool
    def validate_inputs(tool_name, inputs)
      contract = get_contract(tool_name)
      return { valid: false, errors: ["Unknown tool: #{tool_name}"] } unless contract
      
      schema = contract[:input_schema]
      return { valid: true, errors: [] } unless schema
      
      begin
        JSON::Validator.validate!(schema, inputs)
        { valid: true, errors: [] }
      rescue JSON::Schema::ValidationError => e
        { valid: false, errors: [e.message] }
      rescue => e
        { valid: false, errors: ["Validation error: #{e.message}"] }
      end
    end
    
    # Validate outputs for a tool
    def validate_outputs(tool_name, outputs)
      contract = get_contract(tool_name)
      return { valid: false, errors: ["Unknown tool: #{tool_name}"] } unless contract
      
      schema = contract[:output_schema]
      return { valid: true, errors: [] } unless schema
      
      begin
        JSON::Validator.validate!(schema, outputs)
        { valid: true, errors: [] }
      rescue JSON::Schema::ValidationError => e
        { valid: false, errors: [e.message] }
      rescue => e
        { valid: false, errors: ["Validation error: #{e.message}"] }
      end
    end
    
    # Get all available tools
    def available_tools
      TOOLS.keys
    end
    
    # Get tool metadata
    def tool_info(tool_name)
      contract = get_contract(tool_name)
      return nil unless contract
      
      {
        name: tool_name,
        version: contract[:version],
        description: contract[:description],
        timeout: contract[:timeout],
        retryable: contract[:retryable],
        input_schema: contract[:input_schema],
        output_schema: contract[:output_schema]
      }
    end
    
    # Register a new tool
    def register_tool(name, contract)
      # Validate contract structure
      required_keys = [:version, :description, :input_schema, :output_schema]
      missing_keys = required_keys - contract.keys
      
      if missing_keys.any?
        raise ArgumentError, "Tool contract missing required keys: #{missing_keys.join(', ')}"
      end
      
      # In a real implementation, this would update the registry
      # For now, we'll just validate the structure
      Rails.logger.info "Tool '#{name}' registered successfully (simulated)"
      
      {
        success: true,
        tool: name,
        version: contract[:version]
      }
    end
    
    # Get tools by category
    def tools_by_category
      {
        'Content Generation' => ['generate_landing_page_dsl', 'analyze_landing_page_request', 'process_landing_page_images', 'store_uploaded_images'],
        'Content Processing' => ['compile_landing_page_html'],
        'Data Management' => ['create_contact', 'create_campaign', 'get_contact_groups'],
        'Communication' => ['send_email'],
        'System' => ['get_schema', 'query_data']
      }
    end
    
    # Get tool execution statistics (placeholder)
    def tool_stats(tool_name, period = 30.days)
      {
        tool: tool_name,
        period: period,
        executions: rand(100..1000),
        success_rate: rand(85..99),
        avg_duration: rand(1..10),
        last_executed: rand(1..24).hours.ago
      }
    end
  end
end
