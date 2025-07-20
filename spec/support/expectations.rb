# frozen_string_literal: true

module SpecSupport
  module Expectations
    def expect_to_be_destroyed(object)
      expect { object.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    def expect_not_to_be_destroyed(object)
      expect { object.reload }.not_to raise_error
    end
  end
end
