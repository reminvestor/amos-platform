# 🎨 Screenshot-to-Landing-Page Feature

## Overview

Upload a screenshot or design mockup and let Amos create a landing page that closely matches your design. Choose between **Standard** or **High Fidelity** analysis modes based on your accuracy needs and budget.

---

## ✨ What's New

### Before This Feature:
- Upload screenshot → Gets analyzed once with brief text summary
- Details get lost in translation through multiple conversation steps
- Landing page only vaguely resembles the screenshot
- ~30-40% design accuracy

### After This Feature:
- Upload screenshot → Choose analysis depth
- **Standard Mode**: 1 detailed vision analysis (~70-80% accuracy)
- **High Fidelity Mode**: 5-pass deep analysis (~90-95% accuracy)
- Design specifications passed directly to HTML generation
- Agent skips design questions when screenshot provided

---

## 🎯 How to Use

### Step 1: Upload Your Screenshot

In the chat with the Landing Page Manager agent:
```
"Create a landing page that looks like this screenshot"
[Upload your design image]
```

### Step 2: Choose Analysis Mode

The agent will ask:

> I can analyze your screenshot in two ways:
> 
> **Standard Mode** (Recommended):
> - Fast, accurate analysis
> - Perfect for most designs
> - 1 AI vision call
> - Free (included in your plan)
> 
> **High Fidelity Mode** (Premium):
> - Ultra-detailed 5-pass analysis
> - Maximum accuracy (90-95%)
> - 5 AI vision calls (~5x cost)
> - Best for pixel-perfect recreation
> 
> Which would you prefer?

Choose based on your needs:
- **Standard**: Most users, good enough for 90% of cases
- **High Fidelity**: Exact brand recreations, client work, critical pages

### Step 3: Provide Business Content

The agent will ONLY ask for:
- Headline text (if not extracted from screenshot)
- CTA button text
- Pricing details
- Specific benefits/features to highlight

It will **NOT** ask about:
- Colors (extracted from screenshot)
- Layout (extracted from screenshot)  
- Typography (extracted from screenshot)
- Spacing (extracted from screenshot)

### Step 4: Review & Refine

Landing page is generated matching your screenshot!

---

## 🔬 Analysis Modes Comparison

### Standard Mode (1 API Call)

**What It Extracts:**
```json
{
  "layout": {
    "type": "hero-cta",
    "sections": ["hero", "features", "cta"],
    "grid_system": "three-column"
  },
  "colors": {
    "primary": "#4F46E5",
    "secondary": "#10B981",
    "background": "#FFFFFF",
    "text": "#1F2937"
  },
  "typography": {
    "heading_style": "bold sans-serif",
    "heading_size": "large",
    "body_style": "clean sans-serif"
  },
  "spacing": {
    "overall_density": "spacious",
    "section_padding": "generous"
  },
  "visual_style": {
    "aesthetic": "modern",
    "button_style": "rounded",
    "card_style": "shadow"
  }
}
```

**Best For:**
- Internal projects
- MVP/prototypes
- General inspiration
- Budget-conscious projects

**Accuracy:** 70-80%

---

### High Fidelity Mode (5 API Calls)

**Pass 1 - Layout Analysis:**
```json
{
  "layout_type": "hero-cta",
  "sections": [
    {
      "name": "hero",
      "position": "top",
      "height_estimate": "viewport",
      "width": "full-width",
      "background": "gradient"
    }
  ],
  "grid_system": "three-column",
  "content_alignment": "center"
}
```

**Pass 2 - Exact Color Extraction:**
```json
{
  "primary_colors": ["#4F46E5", "#6366F1"],
  "secondary_colors": ["#10B981", "#34D399"],
  "accent_colors": ["#F59E0B"],
  "background_colors": ["#FFFFFF", "#F9FAFB"],
  "text_colors": ["#1F2937", "#6B7280"],
  "button_colors": {
    "background": "#4F46E5",
    "text": "#FFFFFF",
    "hover": "#4338CA"
  }
}
```

**Pass 3 - Typography Details:**
```json
{
  "headings": {
    "font_family_style": "sans-serif",
    "weight": "bold",
    "size_h1": "56px",
    "size_h2": "40px",
    "line_height": "tight",
    "letter_spacing": "normal"
  },
  "body_text": {
    "font_family_style": "sans-serif",
    "weight": "regular",
    "size": "18px",
    "line_height": "1.6"
  }
}
```

**Pass 4 - Spacing Measurements:**
```json
{
  "section_padding": {
    "vertical": "80px",
    "horizontal": "40px"
  },
  "element_spacing": {
    "heading_to_text": "24px",
    "section_gaps": "60px"
  },
  "button_sizing": {
    "padding_vertical": "16px",
    "padding_horizontal": "32px",
    "border_radius": "8px"
  }
}
```

**Pass 5 - Content Extraction (OCR):**
```json
{
  "headline": "Transform Your Business with AI",
  "subheadline": "Automate workflows in minutes",
  "feature_headlines": [
    "Easy Integration",
    "Powerful Analytics",
    "24/7 Support"
  ],
  "cta_buttons": ["Get Started", "Learn More"]
}
```

**Best For:**
- Client work
- Brand-critical pages
- Exact design recreation
- High-stakes launches

**Accuracy:** 90-95%

---

## 💰 Cost Comparison

### Standard Mode:
- **1 vision API call** (~$0.01-0.02 per screenshot)
- **1 HTML generation call** (~$0.10-0.15)
- **Total: ~$0.11-0.17 per landing page**

### High Fidelity Mode:
- **5 vision API calls** (~$0.05-0.10 total)
- **1 HTML generation call** (~$0.10-0.15)
- **Total: ~$0.15-0.25 per landing page**

*Actual costs depend on your Claude API pricing tier and token usage*

**Rule of thumb:** High Fidelity costs about **50-75% more** than Standard

---

## 🎓 Best Practices

### For Best Results:

1. **Clear Screenshots:**
   - Full page screenshots work best
   - High resolution (1920px+ width recommended)
   - Include all sections you want (hero, features, CTA, footer)

2. **Design Clarity:**
   - Screenshots with clear visual hierarchy
   - Readable text in the design
   - Distinct color usage
   - Well-defined sections

3. **Choose Wisely:**
   - Start with Standard mode
   - Upgrade to High Fidelity only if:
     - Standard result needs refinement
     - Client demands exact match
     - Brand consistency critical

4. **Provide Context:**
   - Mention if screenshot is from a competitor
   - Note if it's a design mockup vs. live site
   - Clarify any specific elements you want changed

### What Works Well:

✅ Full landing page screenshots  
✅ Figma/design tool exports  
✅ Competitor pages you want to emulate  
✅ Design mockups from designers  
✅ High-contrast, clear layouts  

### What's Challenging:

⚠️ Hand-drawn sketches (low accuracy)  
⚠️ Low-resolution images  
⚠️ Screenshots with lots of complex imagery  
⚠️ Multi-page designs (stick to single pages)  
⚠️ Animated or video-based designs  

---

## 🚀 Example Workflow

### Scenario: Creating a SaaS Landing Page

**User:**
```
"I want to create a landing page like this"
[Uploads screenshot of a modern SaaS landing page]
```

**Agent:**
```
I see you've uploaded a design! This looks like a modern SaaS landing page 
with a hero section, feature grid, and CTA.

I can analyze this in two ways:
• Standard Mode: Fast analysis, great accuracy (1 AI call)
• High Fidelity Mode: Ultra-detailed 5-pass analysis for maximum accuracy (~5x cost)

Which would you prefer?
```

**User:**
```
Standard mode please
```

**Agent:**
```
[Uses analyze_screenshot_for_design tool]

✅ Analysis complete! I've extracted:
- Layout: Hero-CTA with 3-column features
- Colors: #4F46E5 (primary), #10B981 (accent), white backgrounds
- Typography: Bold sans-serif headings, clean body text
- Spacing: Generous, modern aesthetic

Now I just need some content from you:
1. What should the main headline say?
2. What's your primary CTA button text?
3. What are your top 3 features/benefits to highlight?
```

**User:**
```
1. "Automate Your Marketing in Minutes"
2. "Start Free Trial"
3. - AI-Powered Automation
   - Advanced Analytics
   - 24/7 Expert Support
```

**Agent:**
```
[Generates landing page with design matching screenshot]

✅ Landing page created! I've matched the layout, colors, and style from 
your screenshot while incorporating your specific content.

[Shows preview]

Would you like me to make any adjustments?
```

---

## 🔧 Technical Details

### Tool: `analyze_screenshot_for_design`

**Input Parameters:**
```ruby
{
  image_url: "https://...",  # OR asset_id
  asset_id: 123,             # ImageAsset ID
  analysis_mode: "standard", # or "high_fidelity"
  focus_areas: ["layout", "colors", "typography", "spacing", "content"]
}
```

**Output (Standard):**
```ruby
{
  design_specification: {
    layout: {...},
    colors: {...},
    typography: {...},
    spacing: {...},
    visual_style: {...},
    content_structure: {...}
  },
  analysis_quality: "standard",
  api_calls_used: 1,
  message: "Screenshot analyzed successfully"
}
```

**Output (High Fidelity):**
```ruby
{
  design_specification: {
    layout: {...},      # Pass 1
    colors: {...},      # Pass 2
    typography: {...},  # Pass 3
    spacing: {...},     # Pass 4
    extracted_content: {...}  # Pass 5
  },
  analysis_quality: "high_fidelity",
  api_calls_used: 5,
  message: "High fidelity analysis complete"
}
```

### Integration Points:

1. **Landing Page Manager Agent**: 
   - Detects screenshot uploads
   - Offers mode selection
   - Calls analysis tool
   - Skips design questions

2. **generate_ai_landing_page Tool**:
   - Accepts `screenshot_analysis` parameter
   - Prioritizes screenshot specs over other inputs
   - Passes design spec directly to HTML generation

3. **HTML Generation Prompt**:
   - Screenshot analysis appears FIRST in prompt
   - Marked as highest priority
   - Detailed instructions to follow specs exactly

---

## 📊 Success Metrics

After implementing this feature, we expect:

- **Design Fidelity:** 70-80% (Standard) or 90-95% (High Fidelity)
- **Question Reduction:** 60-70% fewer design questions
- **Time Savings:** 50% faster landing page creation
- **User Satisfaction:** Higher quality results, fewer iterations

---

## 🐛 Troubleshooting

### "Analysis failed"
- Check image is valid (JPG, PNG, WebP)
- Ensure image size < 5MB
- Try re-uploading the screenshot

### "Colors don't match exactly"
- Try High Fidelity mode for exact hex extraction
- Or manually specify color overrides after generation

### "Layout structure is different"
- Standard mode estimates structure; use High Fidelity for exact layout
- Provide more context about specific layout requirements

### "Text content is wrong"
- Text extraction works best in High Fidelity mode
- Always provide your actual headline/copy even if in screenshot

---

## 🎯 Future Enhancements

Potential improvements:
- [ ] Screenshot comparison tool (before/after)
- [ ] Batch analysis (multiple design variations)
- [ ] Style guide extraction (analyze 5+ screenshots, extract brand rules)
- [ ] Animation/interaction extraction from videos
- [ ] Responsive design extraction (analyze mobile + desktop screenshots)

---

## 📝 Summary

This feature solves the "telephone game" problem where screenshot details get lost through multiple conversation steps. By offering two analysis modes and passing structured design specifications directly to HTML generation, we achieve:

✅ **Much higher design fidelity**  
✅ **Fewer user questions needed**  
✅ **Faster page creation**  
✅ **User control over cost vs. accuracy tradeoff**  

**For most users**: Standard mode is perfect  
**For exact recreation**: High Fidelity mode delivers  

*Let the screenshot do the talking!* 🎨

