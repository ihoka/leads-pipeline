class LeadsController < ApplicationController
  def index
    @leads = Current.workspace.leads
      .includes(:company)
      .order(created_at: :desc)
  end

  def show
    @lead = Current.workspace.leads.includes(company: :evidences).find(params[:id])
  end
end
