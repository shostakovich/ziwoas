require_relative "application_system_test_case"

class LightSettingsDialogTest < ApplicationSystemTestCase
  setup do
    Light.delete_all
    @light = Light.create!(key: "DLG1", name: "Stehlampe", sku: "H607C")
  end

  test "the gear opens the settings as a modal dialog that the close button closes" do
    open_settings

    find("dialog .btn-close").click
    assert_no_selector "#light_settings dialog", visible: :all
  end

  test "Escape closes the settings dialog and the gear opens it again" do
    open_settings

    find("#light_name").send_keys(:escape)
    assert_no_selector "#light_settings dialog", visible: :all

    open_settings
  end

  test "Abbrechen closes the dialog without leaving the page" do
    open_settings

    within("dialog") { click_link "Abbrechen" }
    assert_no_selector "#light_settings dialog", visible: :all
    assert_current_path light_path(@light.key)
  end

  test "a rejected save keeps the dialog open with the errors, a valid one closes it" do
    open_settings

    fill_in "Name", with: ""
    click_button "Speichern"
    assert_selector "dialog.modal[open] .alert-danger", text: "Name"

    fill_in "Name", with: "Leselampe"
    click_button "Speichern"
    assert_no_selector "dialog", visible: :all
    assert_selector "h1", text: "Leselampe"
    assert_equal "Leselampe", @light.reload.name
  end

  private

  def open_settings
    visit light_path(@light.key) unless page.current_path == light_path(@light.key)
    find("a[aria-label='Einstellungen']").click
    assert_selector "dialog.modal[open]"
    assert page.evaluate_script("document.querySelector('dialog.modal').matches(':modal')"),
           "the settings dialog opens as a modal"
  end
end
