class ReviewController < ApplicationController
  def index
    @leads = ReviewQueue.new(workspace: Current.workspace).leads
    @selected = @leads.first
  end

  def show
    @selected = Current.workspace.leads.find(params[:id])

    render partial: "review/detail", locals: { lead: @selected }
  end

  def decide
    lead = Current.workspace.leads.find(params[:id])

    ReviewDecision.record!(
      lead: lead,
      decision: params.require(:decision),
      reason_code: params.require(:reason_code),
      note: params[:note]
    )

    redirect_to review_index_path
  end
end
