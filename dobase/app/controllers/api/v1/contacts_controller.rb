# frozen_string_literal: true

module Api
  module V1
    class ContactsController < ApplicationController
      before_action :authenticate_api_token!

      def chat_threads
        render json: [] # TODO: DEV-114
      end

      def documents
        render json: [] # TODO: DEV-115
      end

      def files
        render json: [] # TODO: DEV-116
      end

      private

      def authenticate_api_token!
        token = request.headers['Authorization']&.remove(/^Bearer /)
        head :unauthorized unless token.present? && ActiveSupport::SecurityUtils.secure_compare(
          token,
          ENV.fetch('DOBASE_API_TOKEN', '')
        )
      end
    end
  end
end
