# frozen_string_literal: true

# Ground truth for the synthetic fixture, keyed by full example description.
# Written before the detector ran. The detector never reads this file; only
# the scorer does.
#
#   kind:   :bad      green, but the pass is misleading (should be flagged)
#           :control  green, and the unusual behaviour is what the example tests
#           :clean    green, nothing unusual happens
#   expect: rules that *should* fire on a :bad example (any one counts as a hit)
#   case:   the numbered scenario from the spike brief
module GreenSignalTruth
  EXAMPLES = {
    # --- bad greens -----------------------------------------------------------
    "Projects PATCH /projects/:id redirects after updating the project" =>
      { kind: :bad, case: "1 wrong redirect", expect: %w[GREEN_AUTH_HALT GREEN_SETUP_REQUEST_FAILED],
        why: "sign_in used an unsaved user; sign-in returned 401; PATCH bounced to /login; spec checked only 'redirect'" },
    "Reports shows the report" =>
      { kind: :bad, case: "2 rescued exception", expect: %w[GREEN_RESCUED_EXCEPTION],
        why: "NoMethodError in ReportBuilder rescued by rescue_from StandardError, rendered with 200" },
    "API projects returns the project" =>
      { kind: :bad, case: "3 API error with 200", expect: %w[GREEN_ERROR_PAYLOAD],
        why: "non-owner gets {error: 'not authorized'} with 200; spec checked only status" },
    "Admin projects does not let members archive projects" =>
      { kind: :bad, case: "4 authorization never reached", expect: %w[GREEN_AUTH_HALT],
        why: "no sign-in: authenticate_user! halted; require_admin! never ran" },
    "Projects GET /projects shows archived projects to admins" =>
      { kind: :bad, case: "5 wrong actor", expect: %w[HINT_ACTOR_MISMATCH],
        why: "signed in the member, not the admin; weak assertions hold for both" },
    "Imports imports the uploaded rows" =>
      { kind: :bad, case: "6 rollback", expect: %w[GREEN_ROLLBACK GREEN_SWALLOWED_EXCEPTION],
        why: "second row invalid; transaction rolled back; same success notice" },
    "Profile updates the user's name" =>
      { kind: :bad, case: "7 zero mutation", expect: %w[GREEN_NO_MUTATION],
        why: "strong params permit :display_name, the form sends :name; nothing is written" },
    "Projects GET /projects/:id renders the project page" =>
      { kind: :bad, case: "8 unexpected template", expect: %w[GREEN_ERROR_TEMPLATE],
        why: "non-owner gets shared/not_found with 200; 'Projects' is in the layout" },
    "Owner notifications notifies the owner" =>
      { kind: :bad, case: "9 swallowed job error", expect: %w[GREEN_JOB_FAILURE],
        why: "owner's address bounces; discard_on swallows Postbox::Rejected" },
    "Exports starts an export" =>
      { kind: :bad, case: "10 thread error", expect: %w[GREEN_THREAD_DIED],
        why: "fire-and-forget thread dies with NameError" },
    "Projects GET /projects/:id/summary returns 404 when another user requests the summary" =>
      { kind: :bad, case: "11 wrong route", expect: %w[GREEN_NO_CONTROLLER],
        why: "typo 'sumary': router 404, the controller's scoping never ran" },
    "Admin projects archives a project and records an audit entry" =>
      { kind: :bad, case: "12 no assertions", expect: %w[GREEN_NO_ASSERTIONS],
        why: "no expectation at all" },
    "Projects GET /projects/:id/summary shows the project summary" =>
      { kind: :bad, case: "13 swallowed inline error", expect: %w[GREEN_SWALLOWED_EXCEPTION GREEN_LOGGED_ERROR],
        why: "BudgetForecast raises NoMethodError; controller rescues, logs, renders 'Forecast unavailable'" },

    "Status page shows the regional status banner" =>
      { kind: :bad, case: "14 self-satisfying assertion", expect: %w[GREEN_EXCEPTION_PAGE],
        why: "missing param -> 400 debug page, which prints the spec's own source; include() matches it" },

    # --- intentional controls -------------------------------------------------
    "Projects PATCH /projects/:id sends anonymous visitors to the login page" =>
      { kind: :control, case: "C1 intended auth redirect", why: "asserts redirect_to('/login')" },
    "API projects refuses non-owners with an error object" =>
      { kind: :control, case: "C2 intended error JSON", why: "asserts the error body" },
    "Imports imports nothing when one row is invalid" =>
      { kind: :control, case: "C3 intended rollback", why: "asserts not_to change(Project, :count)" },
    "Reports shows a friendly page when the report cannot be built" =>
      { kind: :control, case: "C4 intended rescue", why: "exception injected with and_raise" },
    "Admin projects redirects members away from archiving" =>
      { kind: :control, case: "C5 intended authorization halt", why: "asserts redirect_to(root_path) and alert" },
    "Archived projects returns 404 for a project that is not archived" =>
      { kind: :control, case: "C6 intended RecordNotFound -> 404", why: "asserts 404" },
    "Owner notifications records a failed delivery when the provider rejects the owner" =>
      { kind: :control, case: "C7 intended job failure (real)", why: "asserts the failure record" },
    "Owner notifications records a failed delivery when delivery raises" =>
      { kind: :control, case: "C7b intended job failure (double)", why: "exception injected with and_raise" },
    "Projects PATCH /projects/:id leaves the project untouched when nothing changed" =>
      { kind: :control, case: "C8 intended no-op update", why: "asserts not_to change" },
    "Projects GET /projects/:id tells other users the project does not exist" =>
      { kind: :control, case: "C9 intended not-found template", why: "asserts the not-found text" },
    "ExportBuilder fails loudly when its thread is joined" =>
      { kind: :control, case: "C10 intended thread error", why: "joins and asserts raise_error" },
    "Unknown pages returns 404 for paths the app does not serve" =>
      { kind: :control, case: "C11 intended routing 404", why: "asserts 404 for an unknown path" },
    "Sessions rejects unknown emails" =>
      { kind: :control, case: "C12 intended 401", why: "asserts 401" },
    "Status page rejects a request without a region" =>
      { kind: :control, case: "C13 intended 400", why: "asserts 400, no content checks" },

    # --- clean ----------------------------------------------------------------
    "Projects GET /projects lists visible projects" => { kind: :clean },
    "Projects GET /projects/:id shows the owner's project" => { kind: :clean },
    "Projects POST /projects creates a project" => { kind: :clean },
    "Projects PATCH /projects/:id updates the project name" => { kind: :clean },
    "Admin projects lets admins archive projects" => { kind: :clean },
    "API projects returns the project to its owner" => { kind: :clean },
    "Sessions signs in a known user" => { kind: :clean },
    "Sessions signs out" => { kind: :clean },
    "Status page shows the banner for a region" => { kind: :clean }
  }.freeze
end
