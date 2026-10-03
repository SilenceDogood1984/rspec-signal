# frozen_string_literal: true

class ExportBuilder
  def initialize(project_id)
    @project_id = project_id
  end

  # Defect: the serializer was renamed and this reference was not.
  def call
    ProjectCsvSerializer.new(@project_id).to_csv
  end
end
