# frozen_string_literal: true

require 'test_helper'

class FrontendDesignExpertTest < ActiveSupport::TestCase
  # ============================================
  # COMPONENT LIBRARY TESTS
  # ============================================

  test 'component library includes all major component types' do
    library = Agents::FrontendDesignExpert::COMPONENT_LIBRARY
    
    assert library.key?(:hero), 'Missing hero components'
    assert library.key?(:features), 'Missing features components'
    assert library.key?(:testimonials), 'Missing testimonials components'
    assert library.key?(:pricing), 'Missing pricing components'
    assert library.key?(:forms), 'Missing forms components'
    assert library.key?(:navigation), 'Missing navigation components'
    assert library.key?(:footer), 'Missing footer components'
    assert library.key?(:cta), 'Missing CTA components'
  end

  test 'each component type has multiple variants' do
    library = Agents::FrontendDesignExpert::COMPONENT_LIBRARY
    
    library.each do |type, config|
      assert config.key?(:variants), "#{type} missing variants"
      assert config[:variants].size >= 2, "#{type} should have at least 2 variants"
      
      config[:variants].each do |variant_key, variant|
        assert variant.key?(:name), "#{type}/#{variant_key} missing name"
        assert variant.key?(:description), "#{type}/#{variant_key} missing description"
        assert variant.key?(:classes), "#{type}/#{variant_key} missing classes"
        assert variant.key?(:best_for), "#{type}/#{variant_key} missing best_for"
      end
    end
  end

  test 'hero variants include key styles' do
    variants = Agents::FrontendDesignExpert::COMPONENT_LIBRARY[:hero][:variants]
    
    assert variants.key?(:gradient), 'Missing gradient hero'
    assert variants.key?(:split), 'Missing split hero'
    assert variants.key?(:minimal), 'Missing minimal hero'
  end

  # ============================================
  # DESIGN SYSTEMS TESTS
  # ============================================

  test 'design systems include all major themes' do
    systems = Agents::FrontendDesignExpert::DESIGN_SYSTEMS
    
    assert systems.key?(:modern), 'Missing modern theme'
    assert systems.key?(:minimal), 'Missing minimal theme'
    assert systems.key?(:corporate), 'Missing corporate theme'
    assert systems.key?(:playful), 'Missing playful theme'
    assert systems.key?(:elegant), 'Missing elegant theme'
    assert systems.key?(:dark_mode), 'Missing dark_mode theme'
  end

  test 'each design system has required properties' do
    systems = Agents::FrontendDesignExpert::DESIGN_SYSTEMS
    
    systems.each do |key, system|
      assert system.key?(:name), "#{key} missing name"
      assert system.key?(:font_family), "#{key} missing font_family"
      assert system.key?(:heading_font), "#{key} missing heading_font"
      assert system.key?(:border_radius), "#{key} missing border_radius"
      assert system.key?(:colors), "#{key} missing colors"
      assert system.key?(:best_for), "#{key} missing best_for"
      
      # Check required colors
      colors = system[:colors]
      assert colors.key?(:primary), "#{key} missing primary color"
      assert colors.key?(:secondary), "#{key} missing secondary color"
    end
  end

  # ============================================
  # DESIGN RECOMMENDATIONS TESTS
  # ============================================

  test 'recommends appropriate design system for SaaS' do
    recommendations = Agents::FrontendDesignExpert.recommend_design_system(
      business_type: 'saas'
    )
    
    assert recommendations.is_a?(Array)
    assert recommendations.any? { |r| r[:key] == :modern }
  end

  test 'recommends appropriate design system for luxury brand' do
    recommendations = Agents::FrontendDesignExpert.recommend_design_system(
      business_type: 'luxury'
    )
    
    assert recommendations.is_a?(Array)
    assert recommendations.any? { |r| r[:key] == :elegant }
  end

  test 'recommends appropriate design system for agency' do
    recommendations = Agents::FrontendDesignExpert.recommend_design_system(
      business_type: 'agency'
    )
    
    assert recommendations.is_a?(Array)
    assert recommendations.any? { |r| r[:key] == :minimal }
  end

  # ============================================
  # CSS VARIABLE GENERATION TESTS
  # ============================================

  test 'generates valid CSS variables for modern theme' do
    css = Agents::FrontendDesignExpert.generate_css_variables(:modern)
    
    assert css.present?
    assert css.include?(':root'), 'Missing :root declaration'
    assert css.include?('--bs-primary'), 'Missing primary color variable'
    assert css.include?('--bs-secondary'), 'Missing secondary color variable'
    assert css.include?('--bs-font-sans-serif'), 'Missing font family variable'
    assert css.include?('--bs-border-radius'), 'Missing border radius variable'
  end

  test 'generates dark mode specific CSS' do
    css = Agents::FrontendDesignExpert.generate_css_variables(:dark_mode)
    
    assert css.present?
    assert css.include?('--bs-body-bg'), 'Dark mode should have background variable'
    assert css.include?('--bs-body-color'), 'Dark mode should have text color variable'
  end

  test 'returns empty string for unknown design system' do
    css = Agents::FrontendDesignExpert.generate_css_variables(:unknown_theme)
    
    assert_equal '', css
  end

  # ============================================
  # COMPONENT TEMPLATE GENERATION TESTS
  # ============================================

  test 'generates hero template for gradient variant' do
    template = Agents::FrontendDesignExpert.get_component_template(:hero, :gradient)
    
    # The method is private, but we can test via send
    template = Agents::FrontendDesignExpert.send(
      :generate_hero_template, 
      :gradient, 
      Agents::FrontendDesignExpert::COMPONENT_LIBRARY[:hero][:variants][:gradient]
    )
    
    assert template.present?
    assert template.include?('section'), 'Template should have section tag'
    assert template.include?('{{headline}}'), 'Template should have headline placeholder'
    assert template.include?('{{cta_url}}'), 'Template should have CTA placeholder'
  end

  test 'generates split hero template' do
    template = Agents::FrontendDesignExpert.send(
      :generate_hero_template, 
      :split, 
      Agents::FrontendDesignExpert::COMPONENT_LIBRARY[:hero][:variants][:split]
    )
    
    assert template.present?
    assert template.include?('col-lg-6'), 'Split hero should have 2 columns'
    assert template.include?('{{hero_image}}'), 'Split hero should have image placeholder'
  end

  # ============================================
  # INTEGRATION TESTS
  # ============================================

  test 'component library and design systems are compatible' do
    # Each component's classes should use Bootstrap classes
    library = Agents::FrontendDesignExpert::COMPONENT_LIBRARY
    
    library.each do |type, config|
      config[:variants].each do |variant_key, variant|
        classes = variant[:classes]
        
        # Classes should be Bootstrap-compatible (contain common Bootstrap class names)
        assert(
          classes.include?('row') || 
          classes.include?('col') || 
          classes.include?('container') ||
          classes.include?('d-flex') ||
          classes.include?('btn') ||
          classes.include?('card') ||
          classes.include?('nav') ||
          classes.include?('bg-') ||
          classes.include?('py-') ||
          classes.include?('position-') ||
          classes.include?('text-'),
          "#{type}/#{variant_key} should use Bootstrap classes, got: #{classes}"
        )
      end
    end
  end
end

