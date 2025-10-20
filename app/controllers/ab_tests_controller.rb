class AbTestsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_entity_exists
  before_action :set_ab_test, only: [:show, :edit, :update, :destroy, :start, :pause, :resume, :stop, :complete]

  def index
    @ab_tests = AbTest.where(entity: current_entity).order(created_at: :desc)
    @active_tests = @ab_tests.where(status: 'running')
    @completed_tests = @ab_tests.where(status: 'completed').limit(10)
  end

  def show
    @results = AbTesting::ExperimentService.get_results_summary(@ab_test)
  end

  def new
    @ab_test = AbTest.new(entity: current_entity)
    2.times { @ab_test.variants.build }
  end

  def create
    @ab_test = AbTest.new(ab_test_params)
    @ab_test.entity = current_entity

    if @ab_test.save
      redirect_to ab_test_path(@ab_test), notice: 'A/B test created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @ab_test.update(ab_test_params)
      redirect_to ab_test_path(@ab_test), notice: 'A/B test updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @ab_test.destroy
    redirect_to ab_tests_path, notice: 'A/B test deleted successfully.'
  end

  def start
    if @ab_test.start!
      redirect_to ab_test_path(@ab_test), notice: 'A/B test started successfully.'
    else
      redirect_to ab_test_path(@ab_test), alert: 'Could not start test. Please check that you have at least 2 variants.'
    end
  end

  def pause
    @ab_test.pause!
    redirect_to ab_test_path(@ab_test), notice: 'A/B test paused.'
  end

  def resume
    if @ab_test.resume!
      redirect_to ab_test_path(@ab_test), notice: 'A/B test resumed.'
    else
      redirect_to ab_test_path(@ab_test), alert: 'Could not resume test.'
    end
  end

  def stop
    @ab_test.stop!
    redirect_to ab_test_path(@ab_test), notice: 'A/B test stopped.'
  end

  def complete
    if @ab_test.complete!
      redirect_to ab_test_path(@ab_test), notice: 'A/B test completed! Winner selected.'
    else
      redirect_to ab_test_path(@ab_test), alert: 'No statistically significant winner yet. Need more data or force completion.'
    end
  end

  private

  def set_ab_test
    @ab_test = AbTest.where(entity: current_entity).find(params[:id])
  end

  def ab_test_params
    params.require(:ab_test).permit(
      :name, :hypothesis, :testable_type, :testable_id,
      :confidence_level, :minimum_sample_size, :metric,
      metadata: [:auto_complete_enabled, :max_days_to_run],
      variants_attributes: [:id, :name, :traffic_percentage, :is_control, configuration: {}]
    )
  end
end
