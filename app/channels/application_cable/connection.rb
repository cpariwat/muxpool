module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :session_id

    def connect
      self.session_id = find_verified_session
    end

    private

    def find_verified_session
      if request.session[:authenticated]
        request.session.id.to_s
      else
        reject_unauthorized_connection
      end
    end
  end
end
