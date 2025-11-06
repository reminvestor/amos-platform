import { 
  Image as ImageIcon,
  Upload,
  X
} from 'lucide-react';
import { Card } from './ui/card';
import { Button } from './ui/button';
import { useState } from 'react';

export function UploadImage() {
  const [isDragging, setIsDragging] = useState(false);

  return (
    <div className="flex-1 bg-[#0A0E1A] overflow-auto">
      {/* Header */}
      <div className="border-b border-[#1E293B] px-8 py-6">
        <div className="flex items-center gap-3 mb-2">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
            <ImageIcon className="w-5 h-5 text-white" />
          </div>
          <h1 className="text-white">Upload Image</h1>
        </div>
        <p className="text-[#94A3B8] ml-[52px]">Add a new image to your media library</p>
      </div>

      {/* Main content */}
      <div className="p-8 max-w-3xl">
        <Card className="bg-[#1A1F35] border-[#1E293B] p-6">
          <div className="space-y-6">
            {/* Title Input */}
            <div>
              <label className="text-white mb-2 block">Title</label>
              <input 
                type="text"
                placeholder="Enter image title"
                className="w-full bg-[#0F172A] border border-[#1E293B] rounded-lg px-4 py-2.5 text-white placeholder:text-[#64748B] focus:outline-none focus:ring-2 focus:ring-[#7C3AED] focus:border-transparent"
              />
            </div>

            {/* Description Textarea */}
            <div>
              <label className="text-white mb-2 block">Description</label>
              <textarea 
                placeholder="Optional description"
                rows={4}
                className="w-full bg-[#0F172A] border border-[#1E293B] rounded-lg px-4 py-2.5 text-white placeholder:text-[#64748B] resize-none focus:outline-none focus:ring-2 focus:ring-[#7C3AED] focus:border-transparent"
              />
            </div>

            {/* Image File Upload */}
            <div>
              <label className="text-white mb-2 block">Image File</label>
              <div 
                className={`border-2 border-dashed rounded-lg p-12 text-center transition-colors ${
                  isDragging 
                    ? 'border-[#7C3AED] bg-[#7C3AED]/5' 
                    : 'border-[#1E293B] hover:border-[#2D3548]'
                }`}
                onDragOver={(e) => {
                  e.preventDefault();
                  setIsDragging(true);
                }}
                onDragLeave={() => setIsDragging(false)}
                onDrop={(e) => {
                  e.preventDefault();
                  setIsDragging(false);
                }}
              >
                <div className="flex flex-col items-center gap-4">
                  <div className="w-16 h-16 rounded-full bg-[#2D3548] flex items-center justify-center">
                    <ImageIcon className="w-8 h-8 text-[#94A3B8]" />
                  </div>
                  <div>
                    <p className="text-white mb-1">Drag and drop your image here, or click to browse</p>
                    <p className="text-[#64748B] text-sm">Supported formats: JPG, PNG, GIF, WebP</p>
                  </div>
                  <input 
                    type="file" 
                    id="file-upload"
                    accept=".jpg,.jpeg,.png,.gif,.webp"
                    className="hidden"
                  />
                  <label htmlFor="file-upload">
                    <Button 
                      type="button"
                      variant="outline"
                      className="bg-transparent border-[#1E293B] text-white hover:bg-[#1E293B] cursor-pointer"
                      onClick={() => document.getElementById('file-upload')?.click()}
                    >
                      Choose File
                    </Button>
                  </label>
                </div>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex items-center gap-3 pt-4">
              <Button 
                className="bg-[#7C3AED] hover:bg-[#7C3AED]/90 text-white gap-2"
              >
                <Upload className="w-4 h-4" />
                Upload Image
              </Button>
              <Button 
                variant="outline"
                className="bg-transparent border-[#1E293B] text-white hover:bg-[#1E293B]"
              >
                Cancel
              </Button>
            </div>
          </div>
        </Card>
      </div>
    </div>
  );
}
