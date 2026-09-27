# frozen_string_literal: true

# Validation cases reproduced from failures seen while dogfooding rspec-signal
# on a Rails application, rather than written alongside the relationship
# rules. Their ground truth was fixed before the analysis was first run on
# them, and nothing was tuned afterwards: silence is an acceptable outcome, a
# wrong causal group is not.
#
# Library code sits under vendor/gems/<name>-<version>/ so that it is
# classified exactly as an installed gem would be.
module CausalDogfood
  module_function

  def all
    [factory_cascade, mixed_run]
  end

  def filler(count = 40)
    CausalScenarios.filler(count)
  end

  # A minimal ActiveRecord and FactoryBot: validations run inside the gem, and
  # factory definitions have finished evaluating before `save!` raises -- so
  # the first project frame RSpec echoes is each spec's own `create` line.
  def rails_gems
    {
      "vendor/gems/activerecord-7.1.3/lib/active_record.rb" => <<~RUBY,
        module ActiveRecord
          class RecordInvalid < StandardError; end

          class Base
            def self.validates_presence_of(*names)
              (@required ||= []).concat(names)
            end

            def self.required
              @required || []
            end

            def initialize(attributes = {})
              @attributes = attributes
            end

            def save!
              missing = self.class.required.reject { |name| @attributes[name] }
              errors = missing.map { |name| "\#{name.to_s.capitalize} must exist" }
              raise RecordInvalid, "Validation failed: \#{errors.join(", ")}" unless errors.empty?

              self
            end
          end
        end
      RUBY
      "vendor/gems/factory_bot-6.4.6/lib/factory_bot.rb" => <<~RUBY,
        module FactoryBot
          DEFINITIONS = {}

          def self.factory(name, model, &block)
            DEFINITIONS[name] = [model, block]
          end

          def self.run(name, overrides)
            model, block = DEFINITIONS.fetch(name)
            model.new(block.call.merge(overrides))
          end

          module Syntax
            module Methods
              def build(name, **overrides)
                FactoryBot.run(name, overrides)
              end

              def create(name, **overrides)
                build(name, **overrides).save!
              end
            end
          end
        end
      RUBY
      "spec/support/gems.rb" => <<~RUBY
        %w[activerecord-7.1.3 factory_bot-6.4.6].each do |gem|
          $LOAD_PATH.unshift(File.expand_path("../../vendor/gems/\#{gem}/lib", __dir__))
        end
        $LOAD_PATH.unshift(File.expand_path("../../app/models", __dir__))
        require "active_record"
        require "factory_bot"
        RSpec.configure { |config| config.include FactoryBot::Syntax::Methods }
      RUBY
    }
  end

  # Observed: one factory lost its organization association. Seventeen
  # examples failed, reached through subject, let, let!, before hooks and
  # example bodies; one spec wrapped the error in a matcher and one request
  # rescued it into a 422. Two unrelated regressions happened alongside.
  def factory_cascade
    files = rails_gems.merge(
      "app/models/user.rb" => "class User < ActiveRecord::Base\n  validates_presence_of :organization\nend\n",
      "app/signups.rb" => <<~RUBY,
        require "user"
        class Signups
          def create(params)
            User.new(params).save!
            201
          rescue ActiveRecord::RecordInvalid
            422
          end
        end
      RUBY
      "spec/factories/users.rb" => <<~RUBY,
        require_relative "../support/gems"
        require "user"
        # The organization association was removed from this factory.
        FactoryBot.factory(:user, User) { { name: "Ada", email: "ada@example.com" } }
      RUBY
      "spec/support/auth.rb" => <<~RUBY,
        module AuthHelpers
          def sign_in(user)
            @current_user = user
          end
        end
        RSpec.configure { |config| config.include AuthHelpers }
      RUBY
      "spec/models/user_spec.rb" => <<~RUBY,
        require_relative "../factories/users"
        RSpec.describe User do
          subject(:user) { create(:user) }
          it("is valid") { expect(user).to be_a(User) }
          it("has a name") { expect(user).to be_truthy }
          it("can be saved twice") { expect(user.save!).to eq(user) }
        end
      RUBY
      "spec/models/membership_spec.rb" => <<~RUBY,
        require_relative "../factories/users"
        RSpec.describe "Membership" do
          let(:user) { create(:user) }
          it("adds the user") { expect(user).to be_truthy }
          it("removes the user") { expect(user).not_to be_nil }
          it("knows its plan") { expect(:free).to eq(:free) }
        end
      RUBY
      "spec/requests/dashboard_spec.rb" => <<~RUBY,
        require_relative "../factories/users"
        require_relative "../support/auth"
        RSpec.describe "Dashboard" do
          before { sign_in create(:user) }
          it("shows projects") { expect(@current_user).to be_truthy }
          it("shows invoices") { expect(@current_user).to be_truthy }
          it("shows the team") { expect(@current_user).to be_truthy }
          it("shows settings") { expect(@current_user).to be_truthy }
        end
      RUBY
      "spec/requests/settings_spec.rb" => <<~RUBY,
        require_relative "../factories/users"
        RSpec.describe "Settings" do
          let!(:user) { create(:user) }
          it("updates the email") { expect(user).to be_truthy }
          it("updates the name") { expect(user).to be_truthy }
        end
      RUBY
      "spec/policies/project_policy_spec.rb" => <<~RUBY,
        require_relative "../factories/users"
        RSpec.describe "ProjectPolicy" do
          it("lets a member edit") do
            user = create(:user)
            expect(user).to be_truthy
          end

          it("lets a member view") do
            member = create(:user, name: "Grace")
            expect(member).to be_truthy
          end
        end
      RUBY
      "spec/services/signup_spec.rb" => <<~RUBY,
        require_relative "../factories/users"
        RSpec.describe "Signup" do
          it("creates a user") { expect { create(:user) }.not_to raise_error }
        end
      RUBY
      "spec/requests/signup_request_spec.rb" => <<~RUBY,
        require_relative "../support/gems"
        require_relative "../../app/signups"
        RSpec.describe "POST /signups" do
          it("creates an account") { expect(Signups.new.create(name: "Ada")).to eq(201) }
          it("creates an invited account") { expect(Signups.new.create(name: "Bo", invited: true)).to eq(201) }
        end
      RUBY
      "spec/system/onboarding_spec.rb" => <<~RUBY,
        require_relative "../factories/users"
        RSpec.describe "Onboarding", type: :system do
          before { create(:user) }
          it("walks through setup") { expect(1).to eq(1) }
        end
      RUBY
      "app/invoice_total.rb" => "module InvoiceTotal\n  def self.call(lines)\n    lines.sum\n  end\nend\n",
      "spec/models/invoice_spec.rb" => "require_relative \"../../app/invoice_total\"\nRSpec.describe \"Invoice\" do\n  " \
                                       "it(\"adds a fee\") { expect(InvoiceTotal.call([10, 20])).to eq(32) }\nend\n",
      "spec/lib/slug_spec.rb" => "RSpec.describe \"Slug\" do\n  " \
                                 "it(\"maps a locale\") { expect({ en: \"a\" }.fetch(:fr)).to eq(\"b\") }\nend\n",
      "spec/filler_spec.rb" => filler
    )
    shared = [
      "User is valid", "User has a name", "User can be saved twice",
      "Membership adds the user", "Membership removes the user",
      "Dashboard shows projects", "Dashboard shows invoices", "Dashboard shows the team", "Dashboard shows settings",
      "Settings updates the email", "Settings updates the name",
      "ProjectPolicy lets a member edit", "ProjectPolicy lets a member view",
      "Signup creates a user",
      "POST /signups creates an account", "POST /signups creates an invited account",
      "Onboarding walks through setup"
    ]
    {
      name: "dogfood: factory cascade", dogfood: true, files: files,
      truth: shared.to_h { |description| [description, "A"] }.merge("Invoice adds a fee" => "i1", "Slug maps a locale" => "i2")
    }
  end

  # Observed: a constant was renamed (Billing::TaxRate -> Billing::TaxTable)
  # and every reference to the old name failed, each from its own line, one
  # of them inside a job that wraps errors. Around it, unrelated problems: a
  # date-format regression seen by two assertions, a missing ENV key, a nil,
  # and a different missing constant.
  def mixed_run
    files = {
      "app/billing.rb" => "module Billing\n  class TaxTable\n    def self.rate\n      0.1\n    end\n  end\nend\n",
      "app/invoice.rb" => <<~RUBY,
        require_relative "billing"
        class Invoice
          def initialize(subtotal)
            @subtotal = subtotal
          end

          def total
            @subtotal + (@subtotal * Billing::TaxRate.rate)
          end
        end
      RUBY
      "app/checkout.rb" => <<~RUBY,
        require_relative "billing"
        class Checkout
          def self.call(cents)
            cents + (cents * Billing::TaxRate.rate).round
          end
        end
      RUBY
      "app/order_serializer.rb" => <<~RUBY,
        require_relative "billing"
        class OrderSerializer
          def self.call(order)
            { total: order[:subtotal], tax_rate: Billing::TaxRate.rate }
          end
        end
      RUBY
      "app/invoice_job.rb" => <<~RUBY,
        require_relative "invoice"
        class InvoiceJob
          class Failed < StandardError; end

          def self.perform(subtotal)
            Invoice.new(subtotal).total
          rescue StandardError
            raise Failed, "invoice job failed"
          end
        end
      RUBY
      "app/formatting.rb" => "module Formatting\n  def self.date(year, month, day)\n    format(\"%02d/%02d/%d\", " \
                             "month, day, year)\n  end\nend\n",
      "app/payments.rb" => "module Payments\n  def self.key\n    ENV.fetch(\"RSPEC_SIGNAL_DOGFOOD_STRIPE_KEY\")\n  end\nend\n",
      "app/presenter.rb" => "module Presenter\n  def self.owner(team)\n    team[:owner].fetch(:name)\n  end\nend\n",
      "app/reports.rb" => "module Reports\n  def self.export\n    Exporter.new\n  end\nend\n",
      "spec/invoice_spec.rb" => <<~RUBY,
        require_relative "../app/invoice"
        RSpec.describe "Invoice" do
          it("adds tax") { expect(Invoice.new(100).total).to eq(110.0) }
          it("adds tax to nothing") { expect(Invoice.new(0).total).to eq(0.0) }
        end
      RUBY
      "spec/checkout_spec.rb" => <<~RUBY,
        require_relative "../app/checkout"
        RSpec.describe "Checkout" do
          it("charges tax") { expect(Checkout.call(1000)).to eq(1100) }
          it("charges tax on cents") { expect(Checkout.call(10)).to eq(11) }
        end
      RUBY
      "spec/order_serializer_spec.rb" => "require_relative \"../app/order_serializer\"\nRSpec.describe \"OrderSerializer\" do\n  " \
                                         "it(\"includes the rate\") { expect(OrderSerializer.call(subtotal: 1)[:tax_rate]).to eq(0.1) }\nend\n",
      "spec/invoice_job_spec.rb" => "require_relative \"../app/invoice_job\"\nRSpec.describe \"InvoiceJob\" do\n  " \
                                    "it(\"totals an invoice\") { expect(InvoiceJob.perform(100)).to eq(110.0) }\nend\n",
      "spec/formatting_spec.rb" => "require_relative \"../app/formatting\"\nRSpec.describe \"Formatting\" do\n  " \
                                   "it(\"formats a date\") { expect(Formatting.date(2026, 9, 27)).to eq(\"2026-09-27\") }\nend\n",
      "spec/receipt_spec.rb" => "require_relative \"../app/formatting\"\nRSpec.describe \"Receipt\" do\n  " \
                                "it(\"prints its date\") { expect(\"Paid \#{Formatting.date(2026, 1, 2)}\").to eq(\"Paid 2026-01-02\") }\nend\n",
      "spec/payments_spec.rb" => "require_relative \"../app/payments\"\nRSpec.describe \"Payments\" do\n  " \
                                 "it(\"has a key\") { expect(Payments.key).to be_a(String) }\nend\n",
      "spec/presenter_spec.rb" => "require_relative \"../app/presenter\"\nRSpec.describe \"Presenter\" do\n  " \
                                  "it(\"names an unowned team\") { expect(Presenter.owner({ owner: nil })).to eq(\"nobody\") }\nend\n",
      "spec/reports_spec.rb" => "require_relative \"../app/reports\"\nRSpec.describe \"Reports\" do\n  " \
                                "it(\"exports\") { expect(Reports.export).to be_truthy }\nend\n",
      "spec/filler_spec.rb" => filler
    }
    {
      name: "dogfood: mixed run around a renamed constant", dogfood: true, files: files,
      truth: { "Invoice adds tax" => "A", "Invoice adds tax to nothing" => "A", "Checkout charges tax" => "A",
               "Checkout charges tax on cents" => "A", "OrderSerializer includes the rate" => "A",
               "InvoiceJob totals an invoice" => "A",
               "Formatting formats a date" => "B", "Receipt prints its date" => "B",
               "Payments has a key" => "i1", "Presenter names an unowned team" => "i2", "Reports exports" => "i3" }
    }
  end
end
