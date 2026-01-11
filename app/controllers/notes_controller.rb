class NotesController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  before_action :set_note, only: [:show, :edit, :update, :destroy, :toggle_pin, :archive, :unarchive]
  before_action -> { authorize_owner_or_admin!(@note) }, only: [:destroy]

  layout "customer_admin"

  def index
    @notes = current_user.notes.active.recent
    @pinned_notes = @notes.pinned
    @unpinned_notes = @notes.where(pinned: false)
    @archived_count = current_user.notes.archived.count
  end

  def archived
    @notes = current_user.notes.archived.recent
  end

  def show
  end

  def new
    @note = current_user.notes.build
  end

  def create
    @note = current_user.notes.build(note_params)

    if @note.save
      respond_to do |format|
        format.html { redirect_to notes_path, notice: "Note created." }
        format.json { render json: @note, status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @note.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    if @note.update(note_params)
      respond_to do |format|
        format.html { redirect_to notes_path, notice: "Note updated." }
        format.json { render json: @note }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @note.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @note.destroy
    respond_to do |format|
      format.html { redirect_to notes_path, notice: "Note deleted." }
      format.json { head :no_content }
    end
  end

  def toggle_pin
    @note.toggle_pin!
    respond_to do |format|
      format.html { redirect_to notes_path, notice: @note.pinned? ? "Note pinned." : "Note unpinned." }
      format.json { render json: @note }
    end
  end

  def archive
    @note.archive!
    respond_to do |format|
      format.html { redirect_to notes_path, notice: "Note archived." }
      format.json { render json: @note }
    end
  end

  def unarchive
    @note.unarchive!
    respond_to do |format|
      format.html { redirect_to archived_notes_path, notice: "Note restored." }
      format.json { render json: @note }
    end
  end

  private

  def set_note
    @note = current_user.notes.find(params[:id])
  end

  def note_params
    params.require(:user_note).permit(:title, :content, :color, :pinned)
  end
end
