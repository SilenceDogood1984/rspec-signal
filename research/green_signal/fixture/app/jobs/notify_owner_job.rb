# frozen_string_literal: true

class NotifyOwnerJob < ApplicationJob
  discard_on Postbox::Rejected do |job, _error|
    Delivery.create!(project: job.arguments.first, status: "failed")
  end

  def perform(project)
    Postbox.deliver!(to: project.owner.email)
    Delivery.create!(project: project, status: "sent")
  end
end
