require_relative "application_system_test_case"

class EnergyFlowLayoutTest < ApplicationSystemTestCase
  RINGS = %w[pv grid consumer battery].freeze

  teardown { page.current_window.resize_to(1400, 1400) }

  test "on a desktop each ring's icon and value stand centred in the ring, the icon half its width" do
    assert_centred_rings(width: 1280, height: 900, icon_share: 0.5)
  end

  test "on a phone each ring's icon and value stand centred in the ring, the icon smaller" do
    assert_centred_rings(width: 375, height: 812, icon_share: 0.375)
  end

  private

  def assert_centred_rings(width:, height:, icon_share:)
    page.current_window.resize_to(width, height)
    visit root_path
    assert_selector ".ef-ring", count: 4

    geometry = ring_geometry
    assert_equal RINGS, geometry.map { |ring| ring.fetch("name") }

    geometry.each do |ring|
      name = ring.fetch("name")
      assert_in_delta ring.fetch("ringY"), ring.fetch("blockY"), 2, "#{name}: icon and value off the ring's vertical centre"
      assert_in_delta ring.fetch("ringX"), ring.fetch("blockX"), 2, "#{name}: icon and value off the ring's horizontal centre"
      assert_in_delta ring.fetch("diameter") * icon_share, ring.fetch("icon"), 1, "#{name}: icon size"
      assert_operator ring.fetch("valueBelowIcon"), :>=, 0, "#{name}: the value belongs below the icon"
    end
  end

  def ring_geometry
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".energy-flow svg circle[data-ring]")].map((circle) => {
        const name = circle.dataset.ring
        const ring = circle.getBoundingClientRect()
        const icon = document.querySelector(`.ef-ring[data-ring="${name}"] .ef-icon`).getBoundingClientRect()
        const value = document.querySelector(`.ef-ring[data-ring="${name}"] .ef-value`).getBoundingClientRect()
        const top = Math.min(icon.top, value.top), bottom = Math.max(icon.bottom, value.bottom)
        const left = Math.min(icon.left, value.left), right = Math.max(icon.right, value.right)
        return {
          name, diameter: ring.width, icon: icon.width, valueBelowIcon: value.top - icon.bottom,
          ringX: ring.left + ring.width / 2, ringY: ring.top + ring.height / 2,
          blockX: (left + right) / 2, blockY: (top + bottom) / 2
        }
      })
    JS
  end
end
