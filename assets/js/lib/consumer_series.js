import { tonesByOrder, OTHER_TONE } from "./chart_theme.js"

export const OTHER_LABEL = "Weitere"

// Tones and order follow `rank`, all consumer ids by Ziwoas.Plugs.consumer_rank, the same on
// every page; consumers beyond the free series are summed into one "Weitere".
export function consumerSeries(consumers, values, rank, semantic = [ "solar" ]) {
  const tones = tonesByOrder(rank, semantic)
  const series = consumers
    .filter((consumer) => tones.has(consumer.plug_id))
    .sort((a, b) => rank.indexOf(a.plug_id) - rank.indexOf(b.plug_id))
    .map((consumer) => ({ label: consumer.name, data: values(consumer), tone: tones.get(consumer.plug_id) }))

  const members = consumers
    .filter((consumer) => !tones.has(consumer.plug_id))
    .map((consumer) => ({ label: consumer.name, data: values(consumer) }))
  if (members.length > 0) {
    const length = Math.max(...members.map((member) => member.data.length))
    series.push({
      label: OTHER_LABEL,
      tone: OTHER_TONE,
      members,
      data: Array.from({ length }, (_, index) => +members.reduce((sum, member) => sum + Number(member.data[index] || 0), 0).toFixed(3)),
    })
  }
  return series
}
