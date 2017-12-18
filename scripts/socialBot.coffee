# Description:
#   Example scripts for you to examine and try out.
#
# Notes:
#   They are commented out by default, because most of them are pretty silly and
#   wouldn't be useful and amusing enough for day to day huboting.
#   Uncomment the ones you want to try and experiment with.
#
#   These are from the scripting documentation: https://github.com/github/hubot/blob/master/docs/scripting.md
#
#Commands:
#   SocialBot list - lists all upcoming social events.
#   SocialBot who's in <event> - lists people who have RSVPed to <event>
#   SocialBot organize <event> for <date> at <place> - Adds event to events list and starts an RSVP
#   SocialBot I'm in for <event> - RSVPs you as coming to <event>
#   SocialBot abandon <event> - Remove yourself from <event>
#   SocialBot cancel <event> - removes <event> from upcoming events list
#

parseEvents = (results) ->
  if !results
    return "There are no upcoming social events."
  parsedResults = ["Upcoming Social Events:"]
  for result in results
    parsedResults.push result.name
  return parsedResults.join('\n')


listEvents = (res) ->
  results = res.robot.brain.get('events')
  res.send parseEvents(results)


module.exports = (robot) ->

  robot.brain.set('events', [{'name': 'testEvent'}])

  robot.respond /list/i, listEvents