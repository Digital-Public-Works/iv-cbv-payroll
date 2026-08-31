require 'rails_helper'

RSpec.describe 'rake data_deletion manual erasure' do
  let(:invitation_with_flow) do
    create(:cbv_flow_invitation, client_agency_id: "sandbox",
      cbv_applicant_attributes: { client_agency_id: "sandbox", case_number: "ERASE001" })
  end
  let!(:cbv_flow) { CbvFlow.create_from_invitation(invitation_with_flow, "device_1") }

  # A second applicant under the same partner identifier, whose invitation was
  # never opened: no cbv_flow exists for it.
  let!(:unused_invitation) do
    create(:cbv_flow_invitation, client_agency_id: "sandbox",
      cbv_applicant_attributes: { client_agency_id: "sandbox", case_number: "ERASE001" })
  end

  def capture_task_output
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  # Rake::Task#execute is used rather than #invoke so the :environment
  # prerequisite is not re-run. TaskArguments is built explicitly because
  # redact_ids reads its applicant ids from #extras, which a plain Hash has not
  # got.
  def run(task_name, *values)
    task = Rake::Task[task_name]
    task.reenable
    task.execute(Rake::TaskArguments.new(task.arg_names, values))
  end

  def resolve(agency = "sandbox", identifier = "ERASE001")
    run("data_deletion:resolve", agency, identifier)
  end

  def redact_ids(agency, *ids)
    run("data_deletion:redact_ids", agency, *ids.map(&:to_s))
  end

  def applicant_ids
    DataRetentionService
      .resolve_manual_erasure("sandbox", "ERASE001")
      .applicant_ids
  end

  describe "data_deletion:resolve" do
    it "reports every record the erasure would touch without changing anything" do
      output = capture_task_output { resolve }

      expect(output).to include("applicants=2")
      expect(output).to include("cbv_flows=1")
      expect(output).to include("invitations=2")
      expect(output).to include("applicant_ids=")
      expect(cbv_flow.reload.redacted_at).to be_nil
      expect(unused_invitation.reload.redacted_at).to be_nil
    end

    it "prints the exact next command to run" do
      output = capture_task_output { resolve }
      ids = applicant_ids

      expect(output).to include("data_deletion:redact_ids[sandbox,#{ids.join(',')}]")
    end

    it "does not write the partner_identifier or redacted values to its output" do
      output = capture_task_output { resolve }

      expect(output).to include("resolve:")
      expect(output).not_to include("ERASE001")
    end

    it "aborts on an unknown client_agency_id" do
      expect { capture_task_output { resolve("not_an_agency") } }.to raise_error(SystemExit)
    end

    it "aborts when nothing matches" do
      expect { capture_task_output { resolve("sandbox", "NO_SUCH_ID") } }.to raise_error(SystemExit)
    end
  end

  describe "data_deletion:redact_ids" do
    it "redacts an applicant reached through a cbv_flow" do
      capture_task_output { redact_ids("sandbox", *applicant_ids) }

      expect(cbv_flow.reload.redacted_at).to be_present
      expect(cbv_flow.cbv_applicant.reload.partner_identifier).to eq("REDACTED")
    end

    it "redacts an applicant whose invitation was never opened" do
      expect(unused_invitation.cbv_flows).to be_empty

      capture_task_output { redact_ids("sandbox", *applicant_ids) }

      expect(unused_invitation.reload.redacted_at).to be_present
      expect(unused_invitation.cbv_applicant.reload.partner_identifier).to eq("REDACTED")
    end

    it "labels attempted counts separately from verified counts" do
      output = capture_task_output { redact_ids("sandbox", *applicant_ids) }

      expect(output).to include("ATTEMPTED applicants=2 cbv_flows=1 invitations_without_flows=1")
      expect(output).to include("VERIFIED applicants=2/2 cbv_flows=1/1 invitations=2/2")
      expect(output).to include("COMPLETE")
    end

    it "does not write the partner_identifier to its output" do
      output = capture_task_output { redact_ids("sandbox", *applicant_ids) }

      expect(output).not_to include("ERASE001")
    end

    # The point of taking ids rather than the identifier: after a successful pass
    # the identifier is gone, so a retry keyed on it would find nothing.
    it "can be re-run with the same ids after a successful pass" do
      ids = applicant_ids
      capture_task_output { redact_ids("sandbox", *ids) }

      expect { capture_task_output { redact_ids("sandbox", *ids) } }.not_to raise_error
      expect(cbv_flow.reload.redacted_at).to be_present
    end

    # Regression: an applicant holding BOTH a flow and a separate never-opened
    # invitation. The flow path stamps the applicant, so an applicant-and-flow
    # check would report success while the unopened invitation still held an
    # email address and auth token.
    it "fails the run when an unopened invitation is left unredacted" do
      shared_applicant = invitation_with_flow.cbv_applicant
      create(:cbv_flow_invitation, client_agency_id: "sandbox", cbv_applicant: shared_applicant)

      allow_any_instance_of(DataRetentionService)
        .to receive(:redact_invitation_and_applicant)
        .and_return(nil)

      expect { capture_task_output { redact_ids("sandbox", shared_applicant.id) } }
        .to raise_error(SystemExit)
    end

    # Argyle holds data outside our database, so a failure there leaves nothing
    # for the row-level verification to find. The run must still fail.
    it "reports a failed Argyle deletion as an incomplete run" do
      cbv_flow.update!(argyle_user_id: "argyle-user-1")
      allow_any_instance_of(DataRetentionService)
        .to receive(:delete_argyle_user).and_return(:failed)

      expect { capture_task_output { redact_ids("sandbox", *applicant_ids) } }
        .to raise_error(SystemExit)
    end

    it "refuses a partner identifier passed in place of an id" do
      expect { capture_task_output { run("data_deletion:redact_ids", "sandbox", "ERASE001") } }
        .to raise_error(SystemExit)

      expect(cbv_flow.reload.redacted_at).to be_nil
    end

    it "aborts on an unknown client_agency_id" do
      expect { capture_task_output { redact_ids("not_an_agency", 1) } }.to raise_error(SystemExit)
    end

    it "aborts when no id matches the agency" do
      expect { capture_task_output { redact_ids("sandbox", 999_999) } }.to raise_error(SystemExit)
    end

    it "does not touch applicants outside the resolved id set" do
      other = create(:cbv_flow_invitation, client_agency_id: "sandbox",
        cbv_applicant_attributes: { client_agency_id: "sandbox", case_number: "KEEP001" })

      capture_task_output { redact_ids("sandbox", *applicant_ids) }

      expect(other.reload.redacted_at).to be_nil
      expect(other.cbv_applicant.reload.partner_identifier).to eq("KEEP001")
    end
  end
end
