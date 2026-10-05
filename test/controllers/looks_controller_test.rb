require "test_helper"

class LooksControllerTest < ActionDispatch::IntegrationTest
  cover "Look*"
  cover "LooksController*"
  cover "ApplicationController#current_look"

  test "pages draw the Clean look until someone picks Felt" do
    get "/reports"

    assert_select "html[data-look]", 0
    assert_select "meta[name='theme-color'][media='(prefers-color-scheme: light)'][content='#f6f7f9']", 1
    assert_select "meta[name='theme-color'][media='(prefers-color-scheme: dark)'][content='#212529']", 1
    assert_select "header form[action='/look'] button.app-look-toggle[aria-pressed='false']", text: "Filz-Look"
    assert_select "header form[action='/look'] input[name='look'][value='felt']", 1
    assert_select "header form[action='/look'][data-turbo='false']", 1
  end

  test "picking Felt keeps it in a long-lived cookie and draws the felt look" do
    patch "/look", params: { look: "felt" }, headers: { "HTTP_REFERER" => "http://www.example.com/reports" }

    assert_redirected_to "http://www.example.com/reports"
    assert_response :see_other
    set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
    assert_match(/look=felt/, set_cookie)
    assert_match(/expires=/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    expires = Time.httpdate(set_cookie[/expires=([^;]+)/i, 1])
    assert_operator expires, :>, 1.year.from_now

    get "/reports"

    assert_select "html[data-look='felt']", 1
    assert_select "meta[name='theme-color'][media='(prefers-color-scheme: light)'][content='#dbcdb7']", 1
    assert_select "meta[name='theme-color'][media='(prefers-color-scheme: dark)'][content='#242220']", 1
    assert_select "button.app-look-toggle.active[aria-pressed='true']", 1
    assert_select "form[action='/look'] input[name='look'][value='clean']", 1
  end

  test "picking Clean again drops the felt look" do
    patch "/look", params: { look: "felt" }
    patch "/look", params: { look: "clean" }

    assert_equal "clean", cookies[:look]
    get "/"

    assert_select "html[data-look]", 0
  end

  test "without a page to return to it lands on the dashboard" do
    patch "/look", params: { look: "felt" }

    assert_redirected_to root_path
  end

  test "an unknown look is refused and leaves the cookie alone" do
    patch "/look", params: { look: "felt" }
    patch "/look", params: { look: "neon" }

    assert_response :bad_request
    assert_equal "felt", cookies[:look]
  end

  test "a missing look is refused" do
    patch "/look"

    assert_response :bad_request
  end

  test "a forged cookie value reads as Clean" do
    cookies[:look] = "<script>"

    get "/"

    assert_response :success
    assert_select "html[data-look]", 0
    assert_select "meta[name='theme-color'][content='#f6f7f9']", 1
  end
end
