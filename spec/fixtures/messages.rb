# frozen_string_literal: true

# Failure messages as RSpec, rspec-rails and Capybara actually word them.
#
# Modelled on a real 2,085-example Rails suite whose 42 failures were mostly
# downstream symptoms of one broken route: request specs getting 404s where they
# expected 200s and redirects, system specs unable to find a `data-testid` that
# the 404 page never rendered, and request specs whose "actual" value was a
# six-thousand-line Rails exception page.
module Messages
  module_function

  # `expect(response).to have_http_status(200)`
  def http_status(expected: 200, actual: 404)
    ["Failure/Error: expect(response).to have_http_status(#{expected})", "",
     "  expected the response to have status code #{expected} but it was #{actual}"]
  end

  # `expect(response).to have_http_status(:redirect)` -- a class of statuses,
  # not one status, so RSpec words it differently.
  def http_status_class(expected: "redirect", range: "3xx", actual: 404)
    ["Failure/Error: expect(response).to have_http_status(:#{expected})", "",
     "  expected the response to have a #{expected} status code (#{range}) but it was #{actual}"]
  end

  # `find(selector)` -- raises Capybara::ElementNotFound.
  def element_not_found(selector)
    ["Failure/Error: find(#{selector.inspect}).click", "",
     "Capybara::ElementNotFound:",
     "  Unable to find css #{selector.inspect}"]
  end

  # `expect(page).to have_css(selector)` -- the same missing node, reported by
  # the matcher instead, so a different class and a different sentence.
  def no_matches(selector)
    ["Failure/Error: expect(page).to have_css(#{selector.inspect})", "",
     "  expected to find visible css #{selector.inspect} but there were no matches"]
  end

  def routing_error(path)
    ["Failure/Error: get #{path.inspect}", "",
     "ActionController::RoutingError:",
     "  No route matches [GET] #{path.inspect}"]
  end

  # An ordinary matcher failure with nothing diagnostic in it. Several of these
  # must never end up in one cluster just because they share a class.
  def comparison(expected:, actual:)
    ["Failure/Error: expect(value).to eq(#{expected})", "",
     "  expected: #{expected}", "       got: #{actual}", "",
     "  (compared using ==)"]
  end

  # A Rails exception page: a little markup wrapped in a great deal of CSS.
  # `css_rules` is the only knob that matters -- it is what makes the real thing
  # unreadable, and it is what has to disappear.
  def rails_exception_page(error: "NoMethodError", where: "ReaderController#show",
                           detail: "undefined method 'progress' for nil", css_rules: 300)
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Action Controller: Exception caught</title>
        <style>
      #{Array.new(css_rules) { |i| "    .line-#{i} { padding: 0; margin: 0; font-family: monospace; }" }.join("\n")}
        </style>
      </head>
      <body>
        <header><h1>#{error} <span>in #{where}</span></h1></header>
        <main>
          <div class="exception-message"><h2>#{detail}</h2></div>
          <div class="source"><div class="info">Extracted source (around line #14):</div></div>
        </main>
      </body>
      </html>
    HTML
  end

  # How `expect(response.body).to include(...)` renders a whole response: one
  # enormous line, because RSpec inspects the actual value.
  def body_include(expected:, actual:)
    ["Failure/Error: expect(response.body).to include(#{expected.inspect})", "",
     "expected #{actual.inspect} to include #{expected.inspect}"]
  end

  # The same failure when RSpec decides to render a diff as well.
  def body_include_with_diff(expected:, actual:)
    body_include(expected: expected, actual: "#{actual[0, 60]}...") +
      ["", "Diff:", "@@ -1 +1,#{actual.lines.size} @@", "-#{expected}"] +
      actual.lines.map { |line| "+#{line.chomp}" }
  end
end
