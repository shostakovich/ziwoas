require_relative "application_system_test_case"

# Numbers in charts and live widgets read German (lib/format), and the chart
# theme applies them to value axes, tooltips, legends and threshold labels.
class ChartNumbersTest < ApplicationSystemTestCase
  setup { visit root_path }

  test "format writes German numbers with a true minus and a spaced unit" do
    assert_equal [
      "1.980 W", "0 W", "— W", "1.235", "−0,25", "0,00", "0,8 kWh", "76 %", "12,5 %", "— %"
    ], format(<<~JS)
      [
        m.formatWatts(1980.4), m.formatWatts(-0.4), m.formatWatts(null),
        m.formatNumber(1234.5), m.formatNumber(-0.25, { decimals: 2 }), m.formatNumber(-0.004, { decimals: 2 }),
        m.formatNumber(0.8, { decimals: 1, unit: "kWh" }),
        m.formatPercent(76), m.formatPercent(12.5, { decimals: 1 }), m.formatPercent(undefined),
      ]
    JS
  end

  test "a signed flow says its direction in words" do
    words = '{ positive: "lädt", negative: "entlädt" }'
    assert_equal [ "lädt 180 W", "entlädt 1.941 W", "0 W", "— W", "liefert 0,25 kWh" ], format(<<~JS)
      [
        m.formatFlow(180.2, #{words}), m.formatFlow(-1941, #{words}), m.formatFlow(-0.3, #{words}),
        m.formatFlow(null, #{words}),
        m.formatFlow(0.25, { positive: "liefert", negative: "zieht", unit: "kWh", decimals: 2 }),
      ]
    JS
  end

  test "a themed chart ticks, keys and labels in German" do
    result = chart(<<~JS)
      const canvas = document.createElement("canvas")
      canvas.style.cssText = "width:600px;height:300px"
      document.body.appendChild(canvas)
      const chart = new Chart(canvas, {
        type: "line",
        data: {
          labels: [ "a", "b" ],
          datasets: [
            { label: "Akku", data: [ -0.16, 0.3 ], tone: "--viz-battery", flowWords: { positive: "lädt", negative: "entlädt" } },
            { label: "Büro", data: [ 0.25, 0.1 ], tone: "--viz-1", unit: "kWh", decimals: 2 },
            { label: "Null", data: [ 0, 0 ], tone: "--viz-muted", legend: false },
            { label: "Grenzwert", data: [ 0.2, 0.2 ], tone: "--danger", endLabel: "0,2 Grenzwert" },
            { label: "Versteckt", data: [ 0, 0 ], tone: "--viz-2", hidden: true },
          ],
        },
        options: { animation: false, responsive: false, scales: { y: { unit: "W", decimals: 1 } } },
        plugins: [ m.chartTheme ],
      })
      const tooltip = (datasetIndex, dataIndex) => m.tooltipLabel({
        chart, dataset: chart.data.datasets[datasetIndex], parsed: { y: chart.data.datasets[datasetIndex].data[dataIndex] },
      })
      const result = {
        ticks: chart.scales.y.ticks.map((tick) => tick.label),
        legend: chart.legend.legendItems.map((item) => item.text),
        tooltips: [ tooltip(0, 0), tooltip(0, 1), tooltip(1, 0) ],
        drawTime: chart.options.plugins.filler.drawTime,
      }
      chart.destroy()
      canvas.remove()
      return result
    JS

    assert_includes result["ticks"], "−0,10"
    assert_includes result["ticks"], "0,30"
    assert_equal [ "Akku", "Büro" ], result["legend"]
    assert_equal [ "Akku: entlädt 0,2 W", "Akku: lädt 0,3 W", "Büro: 0,25 kWh" ], result["tooltips"]
    assert_equal "beforeDatasetsDraw", result["drawTime"]
  end

  test "the main axes leave the unit to the subtitle and time axes draw no grid" do
    result = chart(<<~JS)
      const canvas = document.createElement("canvas")
      canvas.style.cssText = "width:600px;height:300px"
      document.body.appendChild(canvas)
      const chart = new Chart(canvas, {
        type: "line",
        data: { datasets: [ { label: "PV", data: [ { x: 0, y: 1 }, { x: 3_600_000, y: 2 } ], tone: "--viz-solar" } ] },
        options: {
          animation: false, responsive: false,
          scales: {
            x: m.timeScale(0, 3_600_000),
            y: { title: { display: true, text: "Watt" } },
            ySolar: { position: "right", title: { display: true, text: "W/m²" } },
          },
        },
        plugins: [ m.chartTheme ],
      })
      const { x, y, ySolar } = chart.options.scales
      const result = [ x.title.display, y.title.display, ySolar.title.display, x.grid.drawOnChartArea, y.grid.drawOnChartArea ]
      chart.destroy()
      canvas.remove()
      return result
    JS

    assert_equal [ false, false, true, false, true ], result
  end

  test "an axis dipping below zero ends on a round floor without breaking the tick rhythm" do
    result = chart(<<~JS)
      const canvas = document.createElement("canvas")
      canvas.style.cssText = "width:300px;height:300px"
      document.body.appendChild(canvas)
      const values = [ 800, null, -80, 0 ]
      const chart = new Chart(canvas, {
        type: "line",
        data: { labels: [ "a", "b", "c", "d" ], datasets: [ { label: "Akku", data: values, tone: "--viz-battery" } ] },
        options: {
          animation: false, responsive: false,
          scales: { y: { min: m.roundedFloor(values, 100), afterBuildTicks: m.dropOffStepBound, ticks: { stepSize: 500 } } },
        },
        plugins: [ m.chartTheme ],
      })
      const result = {
        min: chart.scales.y.min,
        ticks: chart.scales.y.ticks.map((tick) => tick.value),
        positive: m.roundedFloor([ 3, 5 ], 100) ?? "none",
        exact: m.roundedFloor([ -200 ], 100),
      }
      chart.destroy()
      canvas.remove()
      return result
    JS

    assert_equal(-100, result["min"])
    assert_equal [ 0, 500, 1000 ], result["ticks"]
    assert_equal "none", result["positive"]
    assert_equal(-200, result["exact"])
  end

  private

  def format(expression)
    evaluate("lib/format", "return #{expression}")
  end

  def chart(body)
    evaluate("lib/chart_theme", body)
  end

  def evaluate(module_name, body)
    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      import("#{module_name}").then((m) => done((() => { #{body} })()))
    JS
  end
end
