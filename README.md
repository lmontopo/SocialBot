# SocialBot

SocialBot is a chat bot built on the [Hubot][hubot] framework. Its purpose is to help organize social events from within your chat app!  SocialBot can create events, let you RSVP to events, and even initiate a poll for the date of events!

Currently SocialBot is designed to work with [lets-chat], but it can easily be adapted to other chat bots that have hubot adapters.

[hubot]: http://hubot.github.com
[lets-chat]: https://github.com/sdelements/lets-chat

### Getting started

After cloning this repository, run `npm install` to download the node dependencies.

SocialBot also uses [redis], so install redis.  On mac, this can be done using `brew install redis`.  Then start redis using `brew services start redis`.

[Redis]: https://redis.io/

### Running SocialBot Locally

You can start SocialBot locally by running:

    % bin/hubot

You'll see some start up output and a prompt:

    [Sat Feb 28 2015 12:38:27 GMT+0000 (GMT)] INFO Using default redis on localhost:6379
    SocialBot>

Then you can interact with SocialBot by typing `SocialBot help`.

    SocialBot> SocialBot help
    SocialBot help - Displays all of the help commands that SocialBot knows about.
    ...

Any of the commands that show up here can be used to interact with SocialBot.


## Adapters

As mentioned above, SocialBot uses the lets-chat adapter.  Here's more info about adapters in case you'd like to use SocialBot with a different chat app.

Adapters are the interface to the service you want your hubot to run on, such
as Campfire or IRC. There are a number of third party adapters that the
community have contributed. Check [Hubot Adapters][hubot-adapters] for the
available ones.

If you would like to run a non-Campfire or shell adapter you will need to add
the adapter package as a dependency to the `package.json` file in the
`dependencies` section.

Once you've added the dependency with `npm install --save` to install it you
can then run hubot with the adapter.

    % bin/hubot -a <adapter>

Where `<adapter>` is the name of your adapter without the `hubot-` prefix.

[hubot-adapters]: https://github.com/github/hubot/blob/master/docs/adapters.md