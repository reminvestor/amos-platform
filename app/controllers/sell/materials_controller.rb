# frozen_string_literal: true

module Sell
  class MaterialsController < Sell::BaseController
    def index
      @materials = [
        { id: 1, name: 'AMOS Logo Pack', type: 'zip', size: '2.5 MB', category: 'branding' },
        { id: 2, name: 'Product Screenshots', type: 'zip', size: '15 MB', category: 'images' },
        { id: 3, name: 'Email Templates', type: 'zip', size: '500 KB', category: 'email' },
        { id: 4, name: 'Social Media Kit', type: 'zip', size: '8 MB', category: 'social' },
        { id: 5, name: 'Pitch Deck', type: 'pdf', size: '3 MB', category: 'presentation' },
        { id: 6, name: 'One-Pager', type: 'pdf', size: '1 MB', category: 'document' }
      ]
    end
    
    def show
      @material = { id: params[:id], name: 'Material', type: 'zip' }
    end
    
    def download
      # Handle download
      redirect_to sell_materials_path, notice: "Download started!"
    end
  end
end
