# Liquid Voting as a Service

[![Actions Status](https://github.com/liquidvotingio/api/workflows/CD/badge.svg)](https://github.com/liquidvotingio/api/actions?query=workflow%3ACD)

A liquid voting service that aims to be easily plugged into proposal-making platforms of different kinds. Learn more about the idea and motivation [on this blog post](https://medium.com/@oliver_azevedo_barnes/liquid-voting-as-a-service-c6e17b81ac1b).

In this repo there's an Elixir/Phoenix GraphQL API implementing the most basic [liquid democracy](https://en.wikipedia.org/wiki/Liquid_democracy) concepts: participants, proposals, votes and delegations.

It's deployed on https://api.liquidvoting.io. See sample queries below, in [Using the API](https://github.com/liquidvotingio/api#using-the-api).

There's [a dockerized version](https://github.com/liquidvotingio/api/packages/81472) of the API. The live API is running on Google Kubernetes Engine. The intention is to make the service easily deployable within a microservices/cloud native context.

You can follow the [project backlog here](https://github.com/orgs/liquidvotingio/projects/1).

The live API is getting ready to be used in production platforms. If you're interested, [let us know](mailto:info@liquidvoting.io) so we can learn more about your project, and we'll provide you with an access key right away.

## Concepts and modeling

Participants are users with a name and email, and they can vote on external content (say a blog post, or a pull request), identified as proposal urls, or delegate their votes to another Participant who can then vote for them, or delegate both votes to a third Participant, and so on.

Votes are yes/no booleans and reference a voter (a Participant) and a proposal_url, and Delegations are references to a delegator (a Participant) and a delegate (another Participant).

Once each vote is created, delegates' votes will have a different VotingWeight based on how many delegations they've received.

A VotingResult is calculated taking the votes and their different weights into account. This is a resource the API exposes as a possible `subscription`, for real-time updates over Phoenix Channels.

The syntax for subscribing, and for all other queries and mutations, can be seen following the setup instructions below.

## Local setup

### Building from the repo

You'll need Elixir 1.10, Phoenix 1.4.10 and Postgres 10 installed.

Clone the repo and:

```
mix deps.get
mix ecto.setup
mix phx.server
```

### Running the dockerized version

__Using docker-compose:__

Clone the repo and:

`$ docker-compose up`

__Running the container:__

Mac OSX:
```
docker run -it --rm \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e DB_USERNAME=postgres \
  -e DB_PASSWORD=postgres \
  -e DB_NAME=liquid_voting_dev \
  -e DB_HOST=host.docker.internal \
  -p 4000:4000 \
  ghcr.io/liquidvotingio/api:latest
```
Linux:
```
docker run -it --rm --network=host \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e DB_USERNAME=postgres \
  -e DB_PASSWORD=postgres \
  -e DB_NAME=liquid_voting_dev \
  -e DB_HOST=127.0.0.1 \
  ghcr.io/liquidvotingio/api:latest
```

(assuming you already have the database up and running)

You can run migrations by passing an `eval` command to the containerized app, like this:

```
docker run -it --rm \
  <same options>
  ghcr.io/liquidvotingio/api:latest eval "LiquidVoting.Release.migrate"
```

### Once you're up and running

Open a GraphiQL window in your browser at http://localhost:4000/graphiql, then configure an `Org-ID` header:

```json
{ "Org-ID": "b7a9cae5-6e3a-48b1-8730-8b5c8d6c9b5a"}
```

You can then use the queries below to interact with the API.

## Using the API

Create votes and delegations using [GraphQL mutations](https://graphql.org/learn/queries/#mutations)

```
mutation {
  createVote(participantEmail: "jane@somedomain.com", proposalUrl:"https://github.com/user/repo/pulls/15", yes: true) {
    participant {
      email
    }
    yes
  }
}

mutation {
  createDelegation(proposalUrl: "https://github.com/user/repo/pulls/15", delegatorEmail: "nelson@somedomain.com", delegateEmail: "liz@somedomain.com") {
    delegator {
      email
    }
    delegate {
      email
    }
  }
}

mutation {
  createVote(participantEmail: "liz@somedomain.com", proposalUrl:"https://github.com/user/repo/pulls/15", yes: false) {
    participant {
      email
    }
    yes
    votingResult {
      inFavor
      against
    }
  }
}

```

Then run some [queries](https://graphql.org/learn/queries/#fields), inserting valid id values where indicated:

```
query {
  participants {
    email
    id
    delegationsReceived {
      delegator {
        email
      }
      delegate {
        email
      }
    }
  }
}

query {
  participant(id: <participant id fetched in previous query>) {
    email
    delegationsReceived {
      delegator {
        email
      }
      delegate {
        email
      }
    }
  }
}

query {
  votes {
    yes
    weight
    proposalUrl
    id
    participant {
      email
    }
  }
}

query {
  vote(id: <vote id fetched in previous query>) {
    yes
    weight
    proposalUrl
    participant {
      email
    }
  }
}

query {
  delegations {
    id
    delegator {
      email
    }
    delegate {
      email
    }
  }
}

query {
  delegation(id: <delegation id fetched in previous query>) {
    delegator {
      email
    }
    delegate {
      email
    }
  }
}

query {
  votingResult(proposalUrl: "https://github.com/user/repo/pulls/15") {
    inFavor
    against
    proposalUrl
  }
}
```

And [subscribe](https://github.com/absinthe-graphql/absinthe/blob/master/guides/subscriptions.md) to voting results (which will react to voting creation):

```
subscription {
  votingResultChange(proposalUrl:"https://github.com/user/repo/pulls/15") {
    inFavor
    against
    proposalUrl
  }
}
```

To see this in action, open a second graphiql window in your browser and run `createVote` mutations there, and watch the subscription responses come through on the first one.

With the examples above, the `inFavor` count should be `1`, and `against` should be `2` since `liz@somedomain.com` had a delegation from `nelson@somedomain.com`.
