# frozen_string_literal: true

# The causal-analysis evaluation corpus.
#
# Each scenario is a small project whose failures have a known cause. Labels:
# failures sharing a label share a cause; a label used once is an independent
# failure. `solvable` says whether the shared causes leave *structural*
# evidence (a shared exception object, origin, missing definition or setup
# step) -- decided when the scenario was written, not after scoring it.
#
# `hints` lists the hint types the run must produce, and no others.
#
# `expect` states what the analysis must conclude about a label:
#   "causal"    all of its failures sit in one causal group
#   "scope"     all of its failures sit in one scope group
#   "unlinked"  none of its failures is in a causal group
module CausalScenarios
  module_function

  def filler(count = 30)
    examples = Array.new(count) { |i| "  it(\"passes #{i}\") { expect(#{i}).to eq(#{i}) }" }
    "RSpec.describe \"Filler\" do\n#{examples.join("\n")}\nend\n"
  end

  def all
    [context_hook, before_hook, let_failure, body_failure, broken_factory, missing_env, missing_constant,
     boot_failure, regression_assertions, independent_regressions, order_pollution, driver_failure,
     mixed_run, environment_replica, reused_exception_instance, unimplemented_feature]
  end

  # 1. before(:context) raising: RSpec hands every example the same object.
  def context_hook
    {
      name: "before(:context) raises", solvable: true,
      files: {
        "spec/support/report_fixtures.rb" => <<~RUBY,
          module ReportFixtures
            def self.seed!
              raise IOError, "could not seed report fixtures: fixtures/reports.yml is empty"
            end
          end
        RUBY
        "spec/reports_spec.rb" => <<~RUBY,
          require_relative "support/report_fixtures"
          RSpec.describe "Reports" do
            before(:context) { ReportFixtures.seed! }
            it("lists reports") { expect(1).to eq(1) }
            it("filters reports") { expect(1).to eq(1) }
            it("exports reports") { expect(1).to eq(1) }
          end
        RUBY
        "lib/pricing.rb" => "module Pricing\n  def self.discount(total)\n    (total / 10) - 1\n  end\nend\n",
        "lib/formatting.rb" => <<~RUBY,
          module Formatting
            SYMBOLS = { usd: "$" }.freeze
            def self.money(amount, currency)
              "\#{SYMBOLS.fetch(currency)}\#{format("%.2f", amount)}"
            end
          end
        RUBY
        "spec/pricing_spec.rb" => "require \"pricing\"\nRSpec.describe \"Pricing\" do\n  " \
                                  "it(\"discounts 10%\") { expect(Pricing.discount(100)).to eq(10) }\nend\n",
        "spec/formatting_spec.rb" => "require \"formatting\"\nRSpec.describe \"Formatting\" do\n  " \
                                     "it(\"formats euros\") { expect(Formatting.money(5, :eur)).to eq(\"€5.00\") }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "Reports lists reports" => "A", "Reports filters reports" => "A", "Reports exports reports" => "A",
               "Pricing discounts 10%" => "i1", "Formatting formats euros" => "i2" },
      expect: { "A" => "causal", "i1" => "unlinked", "i2" => "unlinked" },
      evidence: { "A" => %w[shared_exception_object setup_failure] }
    }
  end

  # 2. A before hook in a shared context (no metadata trace) breaks two
  # files; an unrelated before hook breaks a third for a different reason.
  def before_hook
    {
      name: "shared before hook raises", solvable: true,
      files: {
        "lib/session.rb" => <<~RUBY,
          class Session
            class StoreUnavailable < StandardError; end
            def self.sign_in(_user)
              raise StoreUnavailable, "session store is not configured (SESSION_STORE=redis, no redis_url)"
            end
          end
        RUBY
        "lib/invoice.rb" => "class Invoice\n  def self.prepare!\n    raise \"invoice template missing: " \
                            "templates/invoice.html.erb\"\n  end\nend\n",
        "lib/search.rb" => "module Search\n  def self.normalize(text)\n    text.strip\n  end\nend\n",
        "spec/support/auth.rb" => <<~RUBY,
          require "session"
          RSpec.shared_context "signed in admin" do
            before { Session.sign_in(:admin) }
          end
        RUBY
        "spec/admin/reports_spec.rb" => <<~RUBY,
          require_relative "../support/auth"
          RSpec.describe "Admin reports" do
            include_context "signed in admin"
            it("lists") { expect(1).to eq(1) }
            it("exports") { expect(1).to eq(1) }
            it("archives") { expect(1).to eq(1) }
          end
        RUBY
        "spec/admin/users_spec.rb" => <<~RUBY,
          require_relative "../support/auth"
          RSpec.describe "Admin users" do
            include_context "signed in admin"
            it("invites") { expect(1).to eq(1) }
            it("suspends") { expect(1).to eq(1) }
          end
        RUBY
        "spec/billing_spec.rb" => <<~RUBY,
          require "invoice"
          RSpec.describe "Billing" do
            before { Invoice.prepare! }
            it("charges") { expect(1).to eq(1) }
            it("refunds") { expect(1).to eq(1) }
          end
        RUBY
        "spec/search_spec.rb" => "require \"search\"\nRSpec.describe \"Search\" do\n  " \
                                 "it(\"downcases\") { expect(Search.normalize(\" Foo \")).to eq(\"foo\") }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "Admin reports lists" => "A", "Admin reports exports" => "A", "Admin reports archives" => "A",
               "Admin users invites" => "A", "Admin users suspends" => "A",
               "Billing charges" => "B", "Billing refunds" => "B", "Search downcases" => "i1" },
      expect: { "A" => "causal", "B" => "causal", "i1" => "unlinked" },
      evidence: { "A" => %w[setup_failure], "B" => %w[setup_failure] }
    }
  end

  # 3. A `let` that raises, used by two files.
  def let_failure
    {
      name: "let raises", solvable: true,
      files: {
        "lib/account.rb" => <<~RUBY,
          class Account
            PLANS = %i[free pro].freeze
            def self.open!(plan:)
              raise ArgumentError, "unknown plan: \#{plan}" unless PLANS.include?(plan)

              new
            end

            def balance
              0
            end
          end
        RUBY
        "spec/accounts_spec.rb" => <<~RUBY,
          require "account"
          RSpec.describe "Accounts" do
            let(:account) { Account.open!(plan: :gold) }
            it("starts empty") { expect(account.balance).to eq(0) }
            it("is persisted") { expect(account).to be_a(Account) }
            it("has a plan") { expect(account).not_to be_nil }
          end
        RUBY
        "spec/statements_spec.rb" => <<~RUBY,
          require "account"
          RSpec.describe "Statements" do
            let(:account) { Account.open!(plan: :gold) }
            it("renders") { expect(account.balance).to eq(0) }
            it("totals") { expect(account.balance + 1).to eq(1) }
          end
        RUBY
        "spec/limits_spec.rb" => "require \"account\"\nRSpec.describe \"Limits\" do\n  " \
                                 "it(\"offers three plans\") { expect(Account::PLANS.size).to eq(3) }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "Accounts starts empty" => "A", "Accounts is persisted" => "A", "Accounts has a plan" => "A",
               "Statements renders" => "A", "Statements totals" => "A", "Limits offers three plans" => "i1" },
      expect: { "A" => "causal", "i1" => "unlinked" },
      evidence: { "A" => %w[failed_in_let] }
    }
  end

  # 4. Plain body errors: the signature already says everything. The analysis
  # should add nothing.
  def body_failure
    {
      name: "example body errors only", solvable: true,
      files: {
        "lib/cart.rb" => "class Cart\n  def self.total(items)\n    items.sum { |item| item.fetch(:price) }\n  end\nend\n",
        "lib/greeter.rb" => "class Greeter\n  def self.greet(user)\n    \"Hi \#{user.name}\"\n  end\nend\n",
        "spec/cart_spec.rb" => <<~RUBY,
          require "cart"
          RSpec.describe "Cart" do
            it("totals one item") { expect(Cart.total([{ name: "a" }])).to eq(1) }
            it("totals two items") { expect(Cart.total([{ name: "a" }, { name: "b" }])).to eq(2) }
            it("totals gifts") { expect(Cart.total([{ gift: true }])).to eq(0) }
          end
        RUBY
        "spec/greeter_spec.rb" => "require \"greeter\"\nRSpec.describe \"Greeter\" do\n  " \
                                  "it(\"greets a guest\") { expect(Greeter.greet(nil)).to eq(\"Hi guest\") }\nend\n",
        "spec/math_spec.rb" => "RSpec.describe \"Math\" do\n  it(\"adds\") { expect(1 + 1).to eq(3) }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "Cart totals one item" => "A", "Cart totals two items" => "A", "Cart totals gifts" => "A",
               "Greeter greets a guest" => "i1", "Math adds" => "i2" },
      expect: { "A" => "unlinked", "i1" => "unlinked", "i2" => "unlinked" }
    }
  end

  # 5. A new model validation breaks the user factory (via `let` and `before`)
  # and an importer that wraps the same error in its own exception class.
  def broken_factory
    {
      name: "broken factory, and the same error wrapped", solvable: true,
      files: {
        "lib/model.rb" => <<~RUBY,
          module Model
            class RecordInvalid < StandardError; end
          end

          class User
            def self.create!(attrs)
              raise Model::RecordInvalid, "Validation failed: Organization must exist" unless attrs[:organization]

              new
            end
          end
        RUBY
        "lib/importer.rb" => <<~RUBY,
          require "model"
          class Importer
            class Failed < StandardError; end
            def self.call(rows)
              rows.each { |row| User.create!(row) }
            rescue Model::RecordInvalid
              raise Failed, "import aborted at row 1"
            end
          end
        RUBY
        "spec/support/factories.rb" => <<~RUBY,
          require "model"
          module Factories
            def self.user(overrides = {})
              User.create!({ name: "Ada" }.merge(overrides))
            end
          end
        RUBY
        "spec/models/user_spec.rb" => <<~RUBY,
          require_relative "../support/factories"
          RSpec.describe "User" do
            let(:user) { Factories.user }
            it("has a name") { expect(user).to be_a(User) }
            it("can sign in") { expect(user).not_to be_nil }
            it("belongs to an organization") { expect(user).to be_truthy }
          end
        RUBY
        "spec/requests/profile_spec.rb" => <<~RUBY,
          require_relative "../support/factories"
          RSpec.describe "Profile page" do
            before { @user = Factories.user }
            it("shows the profile") { expect(@user).to be_a(User) }
            it("edits the profile") { expect(@user).to be_a(User) }
          end
        RUBY
        "spec/importer_spec.rb" => <<~RUBY,
          require "importer"
          RSpec.describe "Importer" do
            it("imports rows") { expect(Importer.call([{ name: "Ada" }])).to be_truthy }
          end
        RUBY
        "spec/organization_spec.rb" => "RSpec.describe \"Organization\" do\n  " \
                                       "it(\"has a default plan\") { expect(:free).to eq(:pro) }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "User has a name" => "A", "User can sign in" => "A", "User belongs to an organization" => "A",
               "Profile page shows the profile" => "A", "Profile page edits the profile" => "A",
               "Importer imports rows" => "A", "Organization has a default plan" => "i1" },
      expect: { "A" => "causal", "i1" => "unlinked" },
      evidence: { "A" => %w[same_underlying_exception setup_code] }
    }
  end

  # 6. One missing ENV key at two call sites; a different missing key, and a
  # KeyError from an ordinary Hash, must stay apart.
  def missing_env
    {
      name: "missing ENV key at two call sites", solvable: true,
      files: {
        "lib/payments.rb" => "module Payments\n  def self.charge(cents)\n    key = ENV.fetch(\"RSPEC_SIGNAL_CORPUS_STRIPE_KEY\")\n    " \
                             "[key, cents]\n  end\nend\n",
        "lib/webhooks.rb" => "module Webhooks\n  def self.verify(payload)\n    secret = ENV.fetch(\"RSPEC_SIGNAL_CORPUS_STRIPE_KEY\")\n    " \
                             "payload == secret\n  end\nend\n",
        "lib/monitoring.rb" => "module Monitoring\n  def self.dsn\n    ENV.fetch(\"RSPEC_SIGNAL_CORPUS_SENTRY_DSN\")\n  end\nend\n",
        "lib/plans.rb" => "module Plans\n  PRICES = { basic: 5 }.freeze\n  def self.price(plan)\n    PRICES.fetch(plan)\n  end\nend\n",
        "spec/payments_spec.rb" => <<~RUBY,
          require "payments"
          RSpec.describe "Payments" do
            it("charges a card") { expect(Payments.charge(100)).to be_truthy }
            it("charges in cents") { expect(Payments.charge(1)).to be_truthy }
          end
        RUBY
        "spec/webhooks_spec.rb" => <<~RUBY,
          require "webhooks"
          RSpec.describe "Webhooks" do
            it("verifies a signature") { expect(Webhooks.verify("x")).to be(false) }
            it("rejects a bad signature") { expect(Webhooks.verify("y")).to be(false) }
          end
        RUBY
        "spec/monitoring_spec.rb" => "require \"monitoring\"\nRSpec.describe \"Monitoring\" do\n  " \
                                     "it(\"reports errors\") { expect(Monitoring.dsn).to be_a(String) }\nend\n",
        "spec/plans_spec.rb" => "require \"plans\"\nRSpec.describe \"Plans\" do\n  " \
                                "it(\"prices enterprise\") { expect(Plans.price(:enterprise)).to eq(99) }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "Payments charges a card" => "A", "Payments charges in cents" => "A",
               "Webhooks verifies a signature" => "A", "Webhooks rejects a bad signature" => "A",
               "Monitoring reports errors" => "i1", "Plans prices enterprise" => "i2" },
      expect: { "A" => "causal", "i1" => "unlinked", "i2" => "unlinked" },
      evidence: { "A" => %w[missing_entity] }
    }
  end

  # 7. One missing constant referenced from app code and from a spec; a
  # different missing constant and an unrelated nil must stay apart.
  def missing_constant
    {
      name: "missing constant, referenced twice", solvable: true,
      files: {
        "lib/billing.rb" => "module Billing\n  def self.charge(order)\n    Invoice.new(order)\n  end\nend\n",
        "lib/reports.rb" => "module Reports\n  def self.export\n    Export.new\n  end\nend\n",
        "lib/profile.rb" => "module Profile\n  def self.display(user)\n    user.name.upcase\n  end\nend\n",
        "spec/billing_spec.rb" => <<~RUBY,
          require "billing"
          RSpec.describe "Billing" do
            it("charges an order") { expect(Billing.charge(1)).to be_truthy }
            it("charges a refund") { expect(Billing.charge(-1)).to be_truthy }
          end
        RUBY
        "spec/invoice_spec.rb" => <<~RUBY,
          require "billing"
          RSpec.describe "Invoice" do
            it("builds") { expect(Billing::Invoice.new(1)).to be_truthy }
            it("numbers itself") { expect(Billing::Invoice.new(2)).to be_truthy }
          end
        RUBY
        "spec/reports_spec.rb" => "require \"reports\"\nRSpec.describe \"Reports\" do\n  " \
                                  "it(\"exports\") { expect(Reports.export).to be_truthy }\nend\n",
        "spec/profile_spec.rb" => "require \"profile\"\nRSpec.describe \"Profile\" do\n  " \
                                  "it(\"displays a guest\") { expect(Profile.display(nil)).to eq(\"GUEST\") }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "Billing charges an order" => "A", "Billing charges a refund" => "A", "Invoice builds" => "A",
               "Invoice numbers itself" => "A", "Reports exports" => "i1", "Profile displays a guest" => "i2" },
      expect: { "A" => "causal", "i1" => "unlinked", "i2" => "unlinked" },
      evidence: { "A" => %w[missing_entity] }
    }
  end

  # 8. A helper every spec file requires fails at boot: one error per file,
  # and no example runs at all.
  def boot_failure
    {
      name: "boot failure across spec files", solvable: true,
      files: {
        "spec/boot_helper.rb" => "DATABASE_URL = ENV.fetch(\"RSPEC_SIGNAL_CORPUS_DATABASE_URL\")\n",
        "spec/users_spec.rb" => "require_relative \"boot_helper\"\nRSpec.describe(\"Users\") { it(\"lists\") { } }\n",
        "spec/orders_spec.rb" => "require_relative \"boot_helper\"\nRSpec.describe(\"Orders\") { it(\"lists\") { } }\n",
        "spec/invoices_spec.rb" => "require_relative \"boot_helper\"\nRSpec.describe(\"Invoices\") { it(\"lists\") { } }\n"
      },
      truth: { "load:spec/users_spec.rb" => "A", "load:spec/orders_spec.rb" => "A", "load:spec/invoices_spec.rb" => "A" },
      expect: { "A" => "causal" },
      evidence: { "A" => %w[outside_examples] }
    }
  end

  # 9. One regression (tax dropped from Order#total), seen by three assertions
  # in three files. Real, shared, and structurally invisible.
  def regression_assertions
    {
      name: "one regression, three assertions", solvable: false,
      files: {
        "lib/order.rb" => <<~RUBY,
          class Order
            TAX = 0.1
            def initialize(subtotal)
              @subtotal = subtotal
            end

            def total
              @subtotal
            end
          end

          module Receipt
            def self.render(order)
              format("Total: $%.2f", order.total)
            end
          end
        RUBY
        "spec/order_spec.rb" => "require \"order\"\nRSpec.describe \"Order\" do\n  " \
                                "it(\"adds tax\") { expect(Order.new(100).total).to eq(110) }\nend\n",
        "spec/receipt_spec.rb" => "require \"order\"\nRSpec.describe \"Receipt\" do\n  " \
                                  "it(\"prints the total\") { expect(Receipt.render(Order.new(100))).to include(\"$110.00\") }\nend\n",
        "spec/checkout_spec.rb" => "require \"order\"\nRSpec.describe \"Checkout\" do\n  " \
                                   "it(\"charges the total\") { expect(Order.new(50).total * 100).to eq(5500) }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "Order adds tax" => "A", "Receipt prints the total" => "A", "Checkout charges the total" => "A" },
      expect: { "A" => "unlinked" }
    }
  end

  # 10. Only independent failures, several built to look alike: the same nil
  # message from two places, one shared example failing identically in two
  # independently broken hosts, and a chokepoint raising different messages.
  def independent_regressions
    {
      name: "independent regressions that look alike", solvable: true,
      files: {
        "lib/profile.rb" => "module Profile\n  def self.display(user)\n    user.name.upcase\n  end\nend\n",
        "lib/team.rb" => "module Team\n  def self.owner_name(team)\n    team.owner.name\n  end\nend\n",
        "lib/service.rb" => <<~RUBY,
          module Service
            class Error < StandardError; end
            def self.check!(name, value)
              raise Error, "\#{name} check failed: \#{value.inspect}" unless value

              value
            end
          end
        RUBY
        "lib/export.rb" => "require \"service\"\nmodule Export\n  def self.run\n    Service.check!(\"export\", nil)\n  end\nend\n",
        "lib/sync.rb" => "require \"service\"\nmodule Sync\n  def self.run\n    Service.check!(\"sync\", false)\n  end\nend\n",
        "lib/endpoints.rb" => "module Endpoints\n  def self.status(_name)\n    404\n  end\nend\n",
        "spec/support/healthy_endpoint.rb" => <<~RUBY,
          RSpec.shared_examples "a healthy endpoint" do
            it("responds 200") { expect(status).to eq(200) }
          end
        RUBY
        "spec/profile_spec.rb" => "require \"profile\"\nRSpec.describe \"Profile\" do\n  " \
                                  "it(\"displays a guest\") { expect(Profile.display(nil)).to eq(\"GUEST\") }\nend\n",
        "spec/team_spec.rb" => "require \"team\"\nTeamRecord = Struct.new(:owner)\nRSpec.describe \"Team\" do\n  " \
                               "it(\"names an unowned team's owner\") { expect(Team.owner_name(TeamRecord.new(nil))).to eq(\"nobody\") }\nend\n",
        "spec/export_spec.rb" => "require \"export\"\nRSpec.describe \"Export\" do\n  it(\"runs\") { Export.run }\nend\n",
        "spec/sync_spec.rb" => "require \"sync\"\nRSpec.describe \"Sync\" do\n  it(\"runs\") { Sync.run }\nend\n",
        "spec/status_spec.rb" => <<~RUBY,
          require "endpoints"
          require_relative "support/healthy_endpoint"
          RSpec.describe "Billing endpoint" do
            let(:status) { Endpoints.status(:billing) }
            it_behaves_like "a healthy endpoint"
          end
          RSpec.describe "Search endpoint" do
            let(:status) { Endpoints.status(:search) }
            it_behaves_like "a healthy endpoint"
          end
        RUBY
        "spec/filler_spec.rb" => filler
      },
      truth: { "Profile displays a guest" => "i1", "Team names an unowned team's owner" => "i2",
               "Export runs" => "i3", "Sync runs" => "i4",
               "Billing endpoint behaves like a healthy endpoint responds 200" => "i5",
               "Search endpoint behaves like a healthy endpoint responds 200" => "i6" },
      expect: { "i1" => "unlinked", "i2" => "unlinked", "i3" => "unlinked", "i4" => "unlinked",
                "i5" => "unlinked", "i6" => "unlinked" },
      hints: %w[same_origin_different_message]
    }
  end

  # 11. Order-dependent pollution: a passing example changes global state.
  def order_pollution
    {
      name: "order-dependent pollution", solvable: false, args: ["--order", "defined"],
      files: {
        "lib/money_format.rb" => <<~RUBY,
          module MoneyFormat
            class << self
              attr_accessor :currency
            end
            self.currency = :usd

            def self.render(amount)
              currency == :usd ? format("$%.2f", amount) : format("€%.2f", amount)
            end
          end
        RUBY
        "spec/a_settings_spec.rb" => <<~RUBY,
          require "money_format"
          RSpec.describe "Settings" do
            it("switches to euros") do
              MoneyFormat.currency = :eur
              expect(MoneyFormat.render(5)).to eq("€5.00")
            end
          end
        RUBY
        "spec/b_price_spec.rb" => "require \"money_format\"\nRSpec.describe \"Price\" do\n  " \
                                  "it(\"renders dollars\") { expect(MoneyFormat.render(5)).to eq(\"$5.00\") }\nend\n",
        "spec/c_receipt_spec.rb" => "require \"money_format\"\nRSpec.describe \"Receipt\" do\n  " \
                                    "it(\"renders its total\") { expect(\"Total: \#{MoneyFormat.render(12)}\").to eq(\"Total: $12.00\") }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "Price renders dollars" => "A", "Receipt renders its total" => "A" },
      expect: { "A" => "unlinked" }
    }
  end

  # 12. The browser driver cannot start a session. The raise site is inside a
  # vendored gem, and specs reach it from a before hook or from the body.
  def driver_failure
    {
      name: "browser driver cannot start", solvable: true,
      files: {
        "vendor/gems/selenium-webdriver-4.20.0/lib/selenium/webdriver.rb" => <<~RUBY,
          module Selenium
            module WebDriver
              module Error
                class WebDriverError < StandardError; end
                class SessionNotCreatedError < WebDriverError; end
              end

              class Driver
                def self.for(_browser)
                  raise Error::SessionNotCreatedError,
                        "session not created: This version of ChromeDriver only supports Chrome version 114"
                end
              end
            end
          end
        RUBY
        "spec/support/browser.rb" => <<~RUBY,
          $LOAD_PATH.unshift(File.expand_path("../../vendor/gems/selenium-webdriver-4.20.0/lib", __dir__))
          require "selenium/webdriver"
          module Browser
            def visit(path)
              @driver ||= Selenium::WebDriver::Driver.for(:chrome)
              path
            end
          end
          RSpec.configure { |config| config.include Browser, type: :system }
        RUBY
        "spec/system/login_spec.rb" => <<~RUBY,
          require_relative "../support/browser"
          RSpec.describe "Login", type: :system do
            before { visit "/login" }
            it("signs in") { expect(1).to eq(1) }
            it("signs out") { expect(1).to eq(1) }
          end
        RUBY
        "spec/system/checkout_spec.rb" => <<~RUBY,
          require_relative "../support/browser"
          RSpec.describe "Checkout", type: :system do
            it("pays") { visit "/cart" }
            it("applies a coupon") { visit "/cart?coupon=x" }
          end
        RUBY
        "spec/system/search_spec.rb" => <<~RUBY,
          require_relative "../support/browser"
          RSpec.describe "Site search", type: :system do
            it("finds a product") { visit "/search?q=x" }
          end
        RUBY
        "spec/models/tag_spec.rb" => "RSpec.describe \"Tag\", type: :model do\n  " \
                                     "it(\"slugs\") { expect(\"A B\".downcase.tr(\" \", \"-\")).to eq(\"a_b\") }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "Login signs in" => "A", "Login signs out" => "A", "Checkout pays" => "A",
               "Checkout applies a coupon" => "A", "Site search finds a product" => "A", "Tag slugs" => "i1" },
      expect: { "i1" => "unlinked" }
    }
  end

  # 13. A realistic mix: a broken shared setup, a missing ENV key at two
  # call sites, and unrelated failures around them.
  def mixed_run
    auth = before_hook[:files].slice("lib/session.rb", "spec/support/auth.rb", "spec/admin/reports_spec.rb",
                                     "spec/admin/users_spec.rb", "lib/search.rb", "spec/search_spec.rb")
    env = missing_env[:files].slice("lib/payments.rb", "lib/webhooks.rb", "lib/plans.rb", "spec/payments_spec.rb",
                                    "spec/webhooks_spec.rb", "spec/plans_spec.rb")
    others = body_failure[:files].slice("lib/greeter.rb", "spec/greeter_spec.rb", "spec/math_spec.rb")
    {
      name: "mixed: setup + missing ENV + independents", solvable: true,
      files: auth.merge(env).merge(others).merge("spec/filler_spec.rb" => filler(40)),
      truth: { "Admin reports lists" => "A", "Admin reports exports" => "A", "Admin reports archives" => "A",
               "Admin users invites" => "A", "Admin users suspends" => "A",
               "Payments charges a card" => "B", "Payments charges in cents" => "B",
               "Webhooks verifies a signature" => "B", "Webhooks rejects a bad signature" => "B",
               "Search downcases" => "i1", "Plans prices enterprise" => "i2", "Greeter greets a guest" => "i3",
               "Math adds" => "i4" },
      expect: { "A" => "causal", "B" => "causal", "i1" => "unlinked", "i2" => "unlinked", "i3" => "unlinked",
                "i4" => "unlinked" },
      evidence: { "A" => %w[setup_failure], "B" => %w[missing_entity] }
    }
  end

  # 14. The shape of this repository's own 9-failure run: a missing
  # executable, seen as a missing artifact, wrong output and a wrong exit
  # status. Two examples pass vacuously. Nothing structural links them.
  def environment_replica
    examples = [
      %(it("merges workers") { run!; JSON.parse(Sandbox.artifact("signal.json")) }),
      %(it("clusters across workers") { run!; JSON.parse(Sandbox.artifact("signal.json")) }),
      %(it("keeps worker output quiet") { run!; JSON.parse(Sandbox.artifact("signal.json")) }),
      %(it("merges full output") { run!; JSON.parse(Sandbox.artifact("signal.json")) }),
      %(it("warns about a missing artifact") { expect(run!.first).to include("worker artifacts were missing") }),
      %(it("warns about a corrupt artifact") { expect(run!.first).to include("aggregation failed") }),
      %(it("rejects inconsistent configuration") { expect(run!.first).to include("inconsistent configuration") }),
      %(it("exits zero when green") { expect(run!.last).to eq(0) }),
      %(it("leaves artifacts on failure") { run!; expect(Dir.glob("tmp/workers/*")).not_to be_empty }),
      %(it("removes artifacts after a failing merge") { run!; expect(Dir.exist?("tmp/workers")).to be(false) }),
      %(it("removes artifacts after a passing merge") { run!; expect(Dir.exist?("tmp/workers")).to be(false) })
    ]
    {
      name: "environment replica (missing executable)", solvable: false,
      files: {
        "spec/support/sandbox.rb" => <<~RUBY,
          require "open3"
          require "json"
          module Sandbox
            def self.run_parallel
              output, status = Open3.capture2e("sh", "-c", "rspec-signal-corpus-missing-runner -n 2")
              [output, status.exitstatus]
            end

            def self.artifact(name)
              File.read(File.join("tmp/rspec-signal-corpus", name))
            end
          end
        RUBY
        "spec/parallel_spec.rb" => <<~RUBY,
          require_relative "support/sandbox"
          RSpec.describe "parallel support" do
            def run!
              Sandbox.run_parallel
            end

          #{examples.map { |line| "  #{line}" }.join("\n")}
          end
        RUBY
        "spec/filler_spec.rb" => filler(40)
      },
      truth: {
        "parallel support merges workers" => "A", "parallel support clusters across workers" => "A",
        "parallel support keeps worker output quiet" => "A", "parallel support merges full output" => "A",
        "parallel support warns about a missing artifact" => "A", "parallel support warns about a corrupt artifact" => "A",
        "parallel support rejects inconsistent configuration" => "A", "parallel support exits zero when green" => "A",
        "parallel support leaves artifacts on failure" => "A"
      },
      expect: { "A" => "scope" }
    }
  end

  # 15. Adversarial: one exception *instance* raised from two unrelated
  # places. Ruby keeps the first backtrace, so the two failures even look
  # identical. RSpec did not share this object; nothing may claim it did.
  def reused_exception_instance
    {
      name: "adversarial: reused exception instance", solvable: true,
      files: {
        "lib/errors.rb" => "module Errors\n  NOT_FOUND = KeyError.new(\"record not found\")\nend\n",
        "lib/users.rb" => "require \"errors\"\nmodule Users\n  def self.find(_id)\n    raise Errors::NOT_FOUND\n  end\nend\n",
        "lib/orders.rb" => "require \"errors\"\nmodule Orders\n  def self.find(_id)\n    raise Errors::NOT_FOUND\n  end\nend\n",
        "spec/users_spec.rb" => "require \"users\"\nRSpec.describe \"Users\" do\n  it(\"finds a user\") { Users.find(1) }\nend\n",
        "spec/orders_spec.rb" => "require \"orders\"\nRSpec.describe \"Orders\" do\n  it(\"finds an order\") { Orders.find(1) }\nend\n",
        "spec/filler_spec.rb" => filler
      },
      truth: { "Users finds a user" => "i1", "Orders finds an order" => "i2" },
      expect: { "i1" => "unlinked", "i2" => "unlinked" },
      hints: %w[reused_exception_instance]
    }
  end

  # 16. Adversarial for scope: a new spec file for an unimplemented feature.
  # Every example fails, each for its own reason. Concentration is real; a
  # shared cause is not -- which is why scope never claims one.
  def unimplemented_feature
    examples = {
      "exports as CSV" => "expect(Exporter.csv([])).to eq(\"\")",
      "exports as JSON" => "expect(Exporter.json([])).to eq(\"[]\")",
      "names the file" => "expect(Exporter.filename).to eq(\"export.csv\")",
      "limits rows" => "expect(Exporter::LIMIT).to eq(1000)"
    }
    body = examples.map { |name, code| "  it(#{name.inspect}) { #{code} }" }.join("\n")
    {
      name: "adversarial: unimplemented feature file", solvable: true,
      files: {
        "lib/exporter.rb" => "module Exporter\nend\n",
        "spec/exporter_spec.rb" => "require \"exporter\"\nRSpec.describe \"Exporter\" do\n#{body}\nend\n",
        "spec/filler_spec.rb" => filler(40)
      },
      truth: examples.keys.each_with_index.to_h { |name, i| ["Exporter #{name}", "i#{i + 1}"] },
      expect: examples.keys.each_with_index.to_h { |_, i| ["i#{i + 1}", "unlinked"] }
    }
  end
end
