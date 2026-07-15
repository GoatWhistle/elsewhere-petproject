class ForecastsController < ApplicationController
  def show
    render json: Foresight::Forecasts.for_future(future_id: params[:id])
  end
end
