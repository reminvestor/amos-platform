#!/usr/bin/env python3
"""
Generate iOS app icons from AMOS logo with proper background.
Creates all required sizes for iOS app icon set.
"""

from PIL import Image, ImageDraw
import os
import math

# iOS app icon sizes (size, scale, filename)
IOS_ICON_SIZES = [
    (20, 1, "Icon-App-20x20@1x.png"),
    (20, 2, "Icon-App-20x20@2x.png"),
    (20, 3, "Icon-App-20x20@3x.png"),
    (29, 1, "Icon-App-29x29@1x.png"),
    (29, 2, "Icon-App-29x29@2x.png"),
    (29, 3, "Icon-App-29x29@3x.png"),
    (40, 1, "Icon-App-40x40@1x.png"),
    (40, 2, "Icon-App-40x40@2x.png"),
    (40, 3, "Icon-App-40x40@3x.png"),
    (60, 2, "Icon-App-60x60@2x.png"),
    (60, 3, "Icon-App-60x60@3x.png"),
    (76, 1, "Icon-App-76x76@1x.png"),
    (76, 2, "Icon-App-76x76@2x.png"),
    (83.5, 2, "Icon-App-83.5x83.5@2x.png"),
    (1024, 1, "Icon-App-1024x1024@1x.png"),
]

# AMOS brand colors
NAVY = (13, 33, 55)  # #0D2137
TEAL = (13, 148, 136)  # #0d9488


def create_gradient_background(size, color1, color2):
    """Create a vertical gradient background."""
    img = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(img)

    for y in range(size):
        # Interpolate between colors
        ratio = y / size
        r = int(color1[0] + (color2[0] - color1[0]) * ratio)
        g = int(color1[1] + (color2[1] - color1[1]) * ratio)
        b = int(color1[2] + (color2[2] - color1[2]) * ratio)
        draw.line([(0, y), (size, y)], fill=(r, g, b))

    return img


def generate_icon(logo_path, output_path, size):
    """Generate a single icon at the specified size."""
    # Create gradient background
    background = create_gradient_background(size, NAVY, TEAL)

    # Load and resize logo
    logo = Image.open(logo_path).convert('RGBA')

    # Calculate logo size (80% of icon size with some padding)
    logo_size = int(size * 0.65)
    logo_resized = logo.resize((logo_size, logo_size), Image.Resampling.LANCZOS)

    # Calculate position to center the logo
    offset = (size - logo_size) // 2

    # Composite logo onto background
    background_rgba = background.convert('RGBA')
    background_rgba.paste(logo_resized, (offset, offset), logo_resized)

    # Convert back to RGB (no alpha for iOS icons)
    final = background_rgba.convert('RGB')
    final.save(output_path, 'PNG')

    return True


def main():
    # Paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    logo_path = os.path.join(project_root, "app/assets/images/Logo_mark.png")
    output_dir = os.path.join(project_root, "flutter_mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset")

    # Also create a copy for App Store Connect upload
    app_store_icon_path = os.path.join(project_root, "flutter_mobile/ios/AppIcon-1024.png")

    if not os.path.exists(logo_path):
        print(f"Error: Logo not found at {logo_path}")
        return 1

    if not os.path.exists(output_dir):
        print(f"Error: Output directory not found at {output_dir}")
        return 1

    print(f"Generating iOS app icons from: {logo_path}")
    print(f"Output directory: {output_dir}")
    print()

    generated = 0
    for base_size, scale, filename in IOS_ICON_SIZES:
        actual_size = int(base_size * scale)
        output_path = os.path.join(output_dir, filename)

        try:
            generate_icon(logo_path, output_path, actual_size)
            print(f"  ✓ {filename} ({actual_size}x{actual_size})")
            generated += 1

            # Also save the 1024 icon separately for App Store Connect
            if actual_size == 1024:
                generate_icon(logo_path, app_store_icon_path, actual_size)
                print(f"  ✓ AppIcon-1024.png (for App Store Connect)")
        except Exception as e:
            print(f"  ✗ {filename}: {e}")

    print()
    print(f"Generated {generated}/{len(IOS_ICON_SIZES)} icons")
    print()
    print(f"App Store icon saved to: {app_store_icon_path}")
    print("Upload this file to App Store Connect for the app icon.")

    return 0


if __name__ == "__main__":
    exit(main())
