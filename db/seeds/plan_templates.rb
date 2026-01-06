# frozen_string_literal: true

# Plan Templates - Pre-built templates for common requests
#
# These templates are matched against user requests and provide
# optimized execution structures based on what works.

Rails.logger.info "🎯 Seeding plan templates..."

templates = [
  {
    name: "Social Media Management App",
    slug: "social_media_app",
    description: "Complete social media management with content calendar, scheduling, and analytics",
    category: "apps",
    complexity: "complex",
    estimated_duration_minutes: 45,
    keywords: %w[social media content calendar posts scheduling analytics twitter instagram facebook linkedin],
    trigger_patterns: [
      'social media (management|system|app)',
      'content calendar',
      'post schedul',
      'social (posts?|content)'
    ],
    common_issues: [
      "OAuth integration complexity",
      "API rate limits for posting",
      "Platform-specific formatting"
    ],
    phases: [
      {
        id: "phase_discovery",
        name: "Discovery",
        description: "Understand social media requirements",
        status: "pending",
        steps: [
          {
            id: "step_1_1",
            name: "Gather Requirements",
            description: "Understand which platforms, posting frequency, and content types",
            agent: nil,
            tools_needed: ["ask_user"],
            status: "pending",
            dependencies: [],
            estimated_minutes: 5
          }
        ]
      },
      {
        id: "phase_design",
        name: "Design",
        description: "Design the app structure",
        status: "pending",
        steps: [
          {
            id: "step_2_1",
            name: "Create App Blueprint",
            description: "Design module structure for posts, calendar, analytics",
            agent: "app_architect",
            tools_needed: ["generate_app_blueprint"],
            status: "pending",
            dependencies: ["step_1_1"],
            estimated_minutes: 10
          },
          {
            id: "step_2_2",
            name: "User Approval",
            description: "Review design with user",
            agent: nil,
            tools_needed: ["ask_user", "load_canvas"],
            status: "pending",
            dependencies: ["step_2_1"],
            requires_input: true,
            estimated_minutes: 5
          }
        ]
      },
      {
        id: "phase_build",
        name: "Build",
        description: "Build all modules",
        status: "pending",
        steps: [
          {
            id: "step_3_1",
            name: "Build Posts Module",
            description: "Create module for social media posts with fields for content, platforms, media",
            agent: "module_architect",
            tools_needed: ["approve_module_design", "update_module"],
            status: "pending",
            dependencies: ["step_2_2"],
            estimated_minutes: 10
          },
          {
            id: "step_3_2",
            name: "Build Calendar Module",
            description: "Create content calendar with scheduling capabilities",
            agent: "module_architect",
            tools_needed: ["approve_module_design", "update_module"],
            status: "pending",
            dependencies: ["step_3_1"],
            estimated_minutes: 10
          },
          {
            id: "step_3_3",
            name: "Build Analytics Module",
            description: "Create analytics tracking for post performance",
            agent: "module_architect",
            tools_needed: ["approve_module_design", "update_module"],
            status: "pending",
            dependencies: ["step_3_2"],
            estimated_minutes: 10
          }
        ]
      },
      {
        id: "phase_test",
        name: "Test",
        description: "Verify everything works",
        status: "pending",
        steps: [
          {
            id: "step_4_1",
            name: "Test & Preview",
            description: "Preview the app and test functionality",
            agent: nil,
            tools_needed: ["preview_app", "load_canvas"],
            status: "pending",
            dependencies: ["step_3_3"],
            estimated_minutes: 5
          }
        ]
      }
    ]
  },
  {
    name: "CRM Pipeline App",
    slug: "crm_pipeline",
    description: "Sales pipeline management with deals, stages, and forecasting",
    category: "apps",
    complexity: "complex",
    estimated_duration_minutes: 40,
    keywords: %w[crm pipeline deals sales opportunities stages forecast revenue],
    trigger_patterns: [
      'crm (system|app|pipeline)',
      'sales pipeline',
      'deal (management|tracking)',
      'opportunity (management|tracking)'
    ],
    phases: [
      {
        id: "phase_discovery",
        name: "Discovery",
        description: "Understand CRM requirements",
        status: "pending",
        steps: [
          {
            id: "step_1_1",
            name: "Gather Requirements",
            description: "Understand pipeline stages, deal fields, and reporting needs",
            agent: nil,
            tools_needed: ["ask_user"],
            status: "pending",
            dependencies: [],
            estimated_minutes: 5
          }
        ]
      },
      {
        id: "phase_design",
        name: "Design",
        description: "Design the CRM structure",
        status: "pending",
        steps: [
          {
            id: "step_2_1",
            name: "Create App Blueprint",
            description: "Design module structure for deals, pipeline, activities",
            agent: "app_architect",
            tools_needed: ["generate_app_blueprint"],
            status: "pending",
            dependencies: ["step_1_1"],
            estimated_minutes: 10
          }
        ]
      },
      {
        id: "phase_build",
        name: "Build",
        description: "Build all modules",
        status: "pending",
        steps: [
          {
            id: "step_3_1",
            name: "Build Deals Module",
            description: "Create deals module with stages, values, and contacts",
            agent: "module_architect",
            tools_needed: ["approve_module_design"],
            status: "pending",
            dependencies: ["step_2_1"],
            estimated_minutes: 15
          },
          {
            id: "step_3_2",
            name: "Build Pipeline View",
            description: "Create Kanban-style pipeline visualization",
            agent: "module_architect",
            tools_needed: ["update_module"],
            status: "pending",
            dependencies: ["step_3_1"],
            estimated_minutes: 10
          }
        ]
      }
    ]
  },
  {
    name: "Email Newsletter System",
    slug: "email_newsletter",
    description: "Newsletter management with subscribers, campaigns, and analytics",
    category: "marketing",
    complexity: "medium",
    estimated_duration_minutes: 30,
    keywords: %w[newsletter email subscribers campaigns mailing list],
    trigger_patterns: [
      'newsletter',
      'email (campaigns?|marketing)',
      'mailing list',
      'subscribers?'
    ],
    phases: [
      {
        id: "phase_discovery",
        name: "Discovery",
        description: "Understand newsletter requirements",
        status: "pending",
        steps: [
          {
            id: "step_1_1",
            name: "Gather Requirements",
            description: "Understand frequency, templates, and subscriber management needs",
            agent: nil,
            tools_needed: ["ask_user"],
            status: "pending",
            dependencies: [],
            estimated_minutes: 5
          }
        ]
      },
      {
        id: "phase_build",
        name: "Build",
        description: "Build newsletter modules",
        status: "pending",
        steps: [
          {
            id: "step_2_1",
            name: "Build Subscriber Module",
            description: "Create subscriber management with signup forms",
            agent: "module_architect",
            tools_needed: ["approve_module_design"],
            status: "pending",
            dependencies: ["step_1_1"],
            estimated_minutes: 10
          },
          {
            id: "step_2_2",
            name: "Build Campaign Module",
            description: "Create campaign creation and sending",
            agent: "module_architect",
            tools_needed: ["approve_module_design"],
            status: "pending",
            dependencies: ["step_2_1"],
            estimated_minutes: 10
          }
        ]
      }
    ]
  },
  {
    name: "Inventory Tracking System",
    slug: "inventory_tracking",
    description: "Track products, stock levels, and reorder alerts using Platform Factory. User collaborates on design before building.",
    category: "modules",
    complexity: "complex",
    estimated_duration_minutes: 10,
    keywords: %w[inventory stock products tracking reorder warehouse supplies materials],
    trigger_patterns: [
      'inventory (tracking|management|system)',
      'stock (levels?|management)',
      'product catalog',
      'reorder (alerts?|notifications?)',
      'build.*(inventory|stock|product)'
    ],
    phases: [
      # Phase 1: Discovery - Work WITH the user to understand their needs
      {
        id: "phase_1_discovery",
        name: "Discovery",
        description: "Understand user's specific inventory needs",
        status: "pending",
        steps: [
          {
            id: "step_1_1",
            name: "Gather Requirements",
            description: "Ask user about their inventory needs: What products? Multiple locations? Reorder alerts? Suppliers?",
            agent: nil,  # AMOS handles directly with user
            tools_needed: ["ask_user"],
            requires_input: true,
            status: "pending",
            dependencies: [],
            estimated_minutes: 3
          }
        ]
      },
      # Phase 2: Design - AI designs but user reviews
      {
        id: "phase_2_design",
        name: "Design",
        description: "Design the module schema collaboratively with user",
        status: "pending",
        steps: [
          {
            id: "step_2_1",
            name: "Design Module Schema",
            description: "Design data models based on gathered requirements. Include fields, relationships, validations.",
            agent: "platform_factory",
            tools_needed: ["design_module_schema"],
            status: "pending",
            dependencies: ["step_1_1"],
            estimated_minutes: 1
          },
          {
            id: "step_2_2",
            name: "Review Design with User",
            description: "Present the proposed schema to user and get feedback. Iterate if needed.",
            agent: nil,
            tools_needed: ["ask_user", "load_canvas"],
            requires_input: true,
            status: "pending",
            dependencies: ["step_2_1"],
            estimated_minutes: 2
          }
        ]
      },
      # Phase 3: Build - Generate all components
      {
        id: "phase_3_build",
        name: "Build",
        description: "Generate all module components based on approved design",
        status: "pending",
        steps: [
          {
            id: "step_3_1",
            name: "Generate Data Models",
            description: "Create ActiveRecord models with fields, validations, associations",
            agent: "platform_factory",
            tools_needed: ["generate_model_code"],
            status: "pending",
            dependencies: ["step_2_2"],
            estimated_minutes: 1
          },
          {
            id: "step_3_2",
            name: "Generate User Interfaces",
            description: "Create dashboard, data grids, and forms",
            agent: "platform_factory",
            tools_needed: ["generate_canvas_code"],
            status: "pending",
            dependencies: ["step_3_1"],
            estimated_minutes: 1
          },
          {
            id: "step_3_3",
            name: "Generate AI Tools",
            description: "Create CRUD tools for AMOS to manage data",
            agent: "platform_factory",
            tools_needed: ["generate_tool_definition"],
            status: "pending",
            dependencies: ["step_3_1"],
            estimated_minutes: 1
          }
        ]
      },
      # Phase 4: Deploy & Validate
      {
        id: "phase_4_deploy",
        name: "Deploy",
        description: "Deploy the module and run validation tests",
        status: "pending",
        steps: [
          {
            id: "step_4_1",
            name: "Deploy Module",
            description: "Create database tables, load dynamic models, register canvases",
            agent: "platform_factory",
            tools_needed: ["register_module_canvas"],
            status: "pending",
            dependencies: ["step_3_1", "step_3_2", "step_3_3"],
            estimated_minutes: 1
          },
          {
            id: "step_4_2",
            name: "Validate Module",
            description: "Run validation tests to ensure everything works correctly",
            agent: "platform_factory",
            tools_needed: ["validate_module"],
            status: "pending",
            dependencies: ["step_4_1"],
            estimated_minutes: 1
          }
        ]
      }
    ]
  },
  {
    name: "Project Management System",
    slug: "project_management",
    description: "Projects, tasks, milestones, and team assignments",
    category: "apps",
    complexity: "complex",
    estimated_duration_minutes: 50,
    keywords: %w[project tasks milestones team assignments deadlines kanban],
    trigger_patterns: [
      'project management',
      'task (management|tracking)',
      'milestones?',
      'team (assignments?|management)'
    ],
    phases: [
      {
        id: "phase_discovery",
        name: "Discovery",
        status: "pending",
        steps: [
          {
            id: "step_1_1",
            name: "Gather Requirements",
            description: "Understand project types, team structure, and workflow",
            agent: nil,
            tools_needed: ["ask_user"],
            status: "pending",
            dependencies: [],
            estimated_minutes: 5
          }
        ]
      },
      {
        id: "phase_design",
        name: "Design",
        status: "pending",
        steps: [
          {
            id: "step_2_1",
            name: "Create App Blueprint",
            description: "Design project, task, and milestone structure",
            agent: "app_architect",
            tools_needed: ["generate_app_blueprint"],
            status: "pending",
            dependencies: ["step_1_1"],
            estimated_minutes: 10
          }
        ]
      },
      {
        id: "phase_build",
        name: "Build",
        status: "pending",
        steps: [
          {
            id: "step_3_1",
            name: "Build Projects Module",
            description: "Create project management with status and timelines",
            agent: "module_architect",
            tools_needed: ["approve_module_design"],
            status: "pending",
            dependencies: ["step_2_1"],
            estimated_minutes: 15
          },
          {
            id: "step_3_2",
            name: "Build Tasks Module",
            description: "Create task management with assignments and dependencies",
            agent: "module_architect",
            tools_needed: ["approve_module_design"],
            status: "pending",
            dependencies: ["step_3_1"],
            estimated_minutes: 15
          }
        ]
      }
    ]
  },
  # Generic custom module - catches all "build me a..." requests
  {
    name: "Custom Business Module",
    slug: "custom_module",
    description: "Build any custom business module with user collaboration. The AI works with the user to design and build exactly what they need.",
    category: "modules",
    complexity: "complex",
    estimated_duration_minutes: 15,
    keywords: %w[build create make custom module app application system tracker manager],
    trigger_patterns: [
      'build (me )?(a|an) ',
      'create (a|an) ',
      'i need (a|an) ',
      'make (me )?(a|an) ',
      'can you (build|create|make)',
      'set up (a|an) '
    ],
    phases: [
      {
        id: "phase_1_discovery",
        name: "Discovery",
        description: "Work with user to understand exactly what they need",
        status: "pending",
        steps: [
          {
            id: "step_1_1",
            name: "Understand Requirements",
            description: "Have a conversation with the user to understand: What problem are they solving? What data do they need to track? What actions do they need to perform? What reports or views do they need?",
            agent: nil,
            tools_needed: ["ask_user"],
            requires_input: true,
            status: "pending",
            dependencies: [],
            estimated_minutes: 5
          }
        ]
      },
      {
        id: "phase_2_design",
        name: "Design",
        description: "Design the solution collaboratively",
        status: "pending",
        steps: [
          {
            id: "step_2_1",
            name: "Design Data Models",
            description: "Based on requirements, design the data models with fields, types, and relationships",
            agent: "platform_factory",
            tools_needed: ["design_module_schema"],
            status: "pending",
            dependencies: ["step_1_1"],
            estimated_minutes: 2
          },
          {
            id: "step_2_2",
            name: "Review & Refine Design",
            description: "Present the design to the user, explain the structure, and iterate based on feedback",
            agent: nil,
            tools_needed: ["ask_user", "load_canvas"],
            requires_input: true,
            status: "pending",
            dependencies: ["step_2_1"],
            estimated_minutes: 3
          }
        ]
      },
      {
        id: "phase_3_build",
        name: "Build",
        description: "Generate all components based on approved design",
        status: "pending",
        steps: [
          {
            id: "step_3_1",
            name: "Generate Models",
            description: "Create database models with validations and associations",
            agent: "platform_factory",
            tools_needed: ["generate_model_code"],
            status: "pending",
            dependencies: ["step_2_2"],
            estimated_minutes: 1
          },
          {
            id: "step_3_2",
            name: "Generate Interfaces",
            description: "Create dashboards, data grids, and forms",
            agent: "platform_factory",
            tools_needed: ["generate_canvas_code"],
            status: "pending",
            dependencies: ["step_3_1"],
            estimated_minutes: 1
          },
          {
            id: "step_3_3",
            name: "Generate Tools",
            description: "Create AI tools so AMOS can help manage the data",
            agent: "platform_factory",
            tools_needed: ["generate_tool_definition"],
            status: "pending",
            dependencies: ["step_3_1"],
            estimated_minutes: 1
          }
        ]
      },
      {
        id: "phase_4_deploy",
        name: "Deploy",
        description: "Deploy and validate",
        status: "pending",
        steps: [
          {
            id: "step_4_1",
            name: "Deploy Module",
            description: "Create database tables and register the module",
            agent: "platform_factory",
            tools_needed: ["register_module_canvas"],
            status: "pending",
            dependencies: ["step_3_1", "step_3_2", "step_3_3"],
            estimated_minutes: 1
          },
          {
            id: "step_4_2",
            name: "Validate & Test",
            description: "Run tests to ensure everything works",
            agent: "platform_factory",
            tools_needed: ["validate_module"],
            status: "pending",
            dependencies: ["step_4_1"],
            estimated_minutes: 1
          }
        ]
      }
    ]
  }
]

templates.each do |template_data|
  template = PlanTemplate.find_or_initialize_by(slug: template_data[:slug])
  template.assign_attributes(template_data)
  
  if template.new_record?
    template.save!
    Rails.logger.info "  ✅ Created template: #{template.name}"
  else
    template.save!
    Rails.logger.info "  🔄 Updated template: #{template.name}"
  end
end

Rails.logger.info "✅ Plan templates seeded: #{PlanTemplate.count} templates"


