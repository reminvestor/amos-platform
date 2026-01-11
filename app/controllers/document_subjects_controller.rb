class DocumentSubjectsController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  before_action :set_document_subject, only: [:show, :edit, :update, :destroy, :move]
  before_action :authorize_destroy!, only: [:destroy]
  layout 'customer_admin'
  
  def index
    @subjects = current_entity.document_subjects.includes(:children, :rag_documents).ordered
    @root_subjects = @subjects.roots
    
    respond_to do |format|
      format.html
      format.json { render json: @subjects }
    end
  end
  
  def show
    @documents = @document_subject.rag_documents
                                 .includes(:document_tags)
                                 .order(created_at: :desc)
                                 .page(params[:page])
  end
  
  def new
    @document_subject = current_entity.document_subjects.build
    @subjects = current_entity.document_subjects.ordered
  end
  
  def create
    @document_subject = current_entity.document_subjects.build(document_subject_params)
    
    if @document_subject.save
      redirect_to documents_path(subject_id: @document_subject.id), 
                  notice: "Collection '#{@document_subject.name}' created successfully."
    else
      @subjects = current_entity.document_subjects.ordered
      render :new
    end
  end
  
  def edit
    @subjects = current_entity.document_subjects.where.not(id: @document_subject.id).ordered
  end
  
  def update
    if @document_subject.update(document_subject_params)
      redirect_to documents_path(subject_id: @document_subject.id), 
                  notice: "Collection updated successfully."
    else
      @subjects = current_entity.document_subjects.where.not(id: @document_subject.id).ordered
      render :edit
    end
  end
  
  def destroy
    # Move all documents to parent subject or remove assignments
    if @document_subject.parent_id
      @document_subject.document_subject_assignments.update_all(
        document_subject_id: @document_subject.parent_id
      )
    else
      @document_subject.document_subject_assignments.destroy_all
    end
    
    # Move children to parent
    @document_subject.children.update_all(parent_id: @document_subject.parent_id)
    
    @document_subject.destroy
    redirect_to documents_path, notice: "Collection deleted successfully."
  end
  
  def move
    new_parent = params[:parent_id].present? ? 
                 current_entity.document_subjects.find(params[:parent_id]) : 
                 nil
    
    if @document_subject.move_to(new_parent)
      render json: { success: true, message: "Collection moved successfully." }
    else
      render json: { success: false, errors: @document_subject.errors.full_messages }
    end
  end
  
  private
  
  def set_document_subject
    @document_subject = current_entity.document_subjects.find(params[:id])
  end
  
  def document_subject_params
    params.require(:document_subject).permit(
      :name, :description, :parent_id, :icon, :color, 
      :is_smart_folder, :rules
    )
  end
end
