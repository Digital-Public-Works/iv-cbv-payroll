class AddLandingPageCompletedAtToCbvFlows < ActiveRecord::Migration[8.1]
  def change
    # Set once the /start landing page has been passed, whether it was shown or
    # skipped because the partner asks for nothing there (or it is already filled).
    add_column :cbv_flows, :landing_page_completed_at, :datetime
  end
end
