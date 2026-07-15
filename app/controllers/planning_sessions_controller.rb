class PlanningSessionsController < ApplicationController
  def create
    session = Planning::Sessions.create(dream_text: payload.fetch("dream_text"), origin: payload.fetch("origin"), date_window: payload.fetch("date_window"), party: payload.fetch("party"))
    render json: Planning::Sessions.public(session), status: :created
  end

  def show
    session = Planning::Sessions.find(id: params[:id])
    raise ActiveRecord::RecordNotFound, "Session not found" unless session
    render json: Planning::Sessions.public(session)
  end

  def update_dna
    render json: Planning::TravelDna.update(session_id: params[:id], elements: payload.fetch("elements"))
  end

  def clarifications
    render json: Planning::TravelDna.answer_clarifications(session_id: params[:id], answers: payload.fetch("answers"))
  end
end
