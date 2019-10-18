# Liquid Voting as a Service

[![Actions Status](https://github.com/oliverbarnes/liquid-voting-service/workflows/CI/badge.svg)](https://github.com/oliverbarnes/liquid-voting-service/actions?workflow=CI)

Early stages of a liquid voting service that aims to be easily plugged into proposal-making platforms of different kinds. Learn more about the idea and motivation [on this Medium post](https://medium.com/@oliver_azevedo_barnes/liquid-voting-as-a-service-c6e17b81ac1b).

It consists of a Elixir/Phoenix GraphQL API implementing the most basic [liquid democracy](https://en.wikipedia.org/wiki/Liquid_democracy) concepts: participants, proposals, votes and delegations.

There's [a dockerized version](https://hub.docker.com/r/oliverbarnes/liquid-voting-service) and manifests to get a rudimentary Kubernetes deployment going for it (a playground). I've been playing with the latter locally and on GKE, and you'll see instructions on how to get it up and running below.

Please note this is nowhere near ready for production use, it doesn't even have authentication. It's just getting beyond a proof of concept.

## Modeling

Participants are simply names with emails, Proposals are links to external content (say a blog post, or a pull request), Votes are booleans and references to a voter (a Participant) and a Proposal, and Delegations are references to a delegator (a Participant) and a delegate (another Participant).

A participant can vote for or against a proposal, or delegate to another participant so they can vote for them. Once each vote is cast, delegates' votes will have a different weight based on how many delegations they've received.

A VotingResult is calculated taking the votes and their different weights into account. This is a resource the API exposes as a possible `subscription`, for real-time updates over Phoenix Channels.

The syntax for this, and for all other queries and mutations, can be seen following the setup.

## Local setup

### Building from the repo

You'll need Elixir 1.9, Phoenix 1.4.10 and Postgres 10 installed.

Clone the repo and:

```
mix deps.get
mix ecto.setup
mix phx.server
```

### Running the dockerized version

```
docker run -it --rm \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e DB_USERNAME=postgres \
  -e DB_PASSWORD=postgres \
  -e DB_NAME=liquid_voting_dev \
  -e DB_HOST=host.docker.internal \
  -p 4000:4000 \
  oliverbarnes/liquid-voting-service:latest
```

(assuming you already have the database up and running)

You can run migrations by passing an `eval` command to the containerized app, like this:

```
docker run -it --rm \
  <same options>
  oliverbarnes/liquid-voting-service:latest eval "LiquidVoting.Release.migrate"
```

### Running it locally in a Kubernetes cluster on Docker for Mac

You'll need [Helm](https://helm.sh/docs/using_helm/#initialize-helm-and-install-tiller) for some of these steps. 

Install the [ingress-nginx controller](https://github.com/kubernetes/ingress-nginx):

```
helm install stable/nginx-ingress \
  --set controller.metrics.enabled=true,controller.metrics.serviceMonitor.enabled=true,controller.stats.enabled=true
```

NOTE: Right now the ingress will run on port 80, not 4000. Still figuring out the right install config to get 4000 going.

Create secrets for the postgres database:

```
kubectl create secret generic liquid-voting-postgres \
--from-literal=postgres-username=postgres \
--from-literal=postgres-password=postgres \
--from-literal=postgres-dbname=liquid_voting_dev \
--from-literal=postgres-host=localhost \
--from-literal=postgres-pool-size=10
```

Then apply the app's manifest files (if you use [Tilt](https://tilt.dev/) you can do `tilt up` instead):

```
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/database-persistent-volume-claim.yaml
kubectl apply -f k8s/database-service.yaml
kubectl apply -f k8s/database-deployment.yaml
kubectl apply -f k8s/liquid-voting-service.yaml
kubectl apply -f k8s/liquid-voting-deployment.yaml
```

And run the migrations from within the app deployment:

```
kubectl get pods
kubectl exec -ti liquid-voting-deployment-pod \
  --container liquid-voting \
  -- /opt/app/_build/prod/rel/liquid_voting/bin/liquid_voting \
  eval "LiquidVoting.Release.migrate"
```

#### If you want to also install monitoring (Prometheus and Grafana)

Install [prometheus-operator](https://github.com/helm/charts/blob/master/stable/prometheus-operator/README.md), which will get you going with both [Prometheus](https://prometheus.io) and [Grafana](https://grafana.com):

```
helm install stable/prometheus-operator
```

The `ingress-nginx` metrics won't be scraped right away. In order to get Prometheus to see them, [you'll need to make the ingress' servicemonitor release label match the one Prometheus expects](https://github.com/coreos/prometheus-operator/issues/2119#issuecomment-439620190). Very hacky and manual, but no way around it as far as I know and after extensive googling:

First take a look at your Prometheus instance's `matchLabel.release` config:

```
kubectl get prometheus prometheus-instance -o yaml
```

Then open your ingress servicemonitor and edit its `metadata.labels.release` to match it:

```
kubectl get servicemonitors
KUBE_EDITOR=your-favorite-editor kubectl edit servicemonitor ingress-controller
```

Expose the Grafana dashboard:

```
export POD_NAME=$(kubectl get pods -l "app=grafana" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $POD_NAME 3000
```

Open [http://localhost:3000](http://localhost:3000) and you'll see a login page.

The password secret was generated during the install, to get it run:

```
kubectl get secret my-release-grafana \
  -o jsonpath="{.data.admin-password}" \
  | base64 --decode ; echo
```

The login user is `admin`.


## Using the API

Once you're up and running, you can use [Absinthe](https://absinthe-graphql.org/)'s handy query runner GUI by opening [http://localhost:4000/graphiql](http://localhost:4000/graphiql).

Start by creating some participants, a proposal, a vote and a delegation using [GraphQL mutations](https://graphql.org/learn/queries/#mutations)

```
mutation {
  createParticipant(name: "Zygmunt Bauman", email: "zyg@bauman.com") {
    name
    email
  }
}

mutation {
  createParticipant(name: "Jane Doe", email: "jane@doe.com") {
    name
    email
  }
}

mutation {
  createProposal(url: "https://www.medium.com/a-proposal") {
    url
  }
}

mutation {
  createVote(participantId: 1, proposalId: 1, yes: true) {
    participant {
      name
      email
    }
    yes
  }
}

mutation {
  createDelegation(proposalId: 1, delegatorId: 2, delegateId: 1) {
    delegator {
      name
      email
    }
    delegate {
      name
      email
    }
  }
}
```

Then run some [queries](https://graphql.org/learn/queries/#fields):

```
query {
  participants {
    id
    name
    email
    delegations_received {
      id
      delegator {
        id
        name
        email
      }
      delegate {
        id
        name
        email
      }
    }
  }
}

query {
  participant(id: 1) {
    id
    name
    email
    delegations_received {
      id
      delegator {
        id
        name
        email
      }
      delegate {
        id
        name
        email
      }
    }
  }
}

query {
  proposals {
    id
    url
  }
}

query {
  proposal(id: 1) {
    id
    url
  }
}

query {
  votes {
    id
    yes
    weight
    participant {
      id
      name
      email
    }
    proposal {
      id
      url
    }
  }
}

query {
  vote(id: 1) {
    id
    yes
    weight
    participant {
      id
      name
      email
    }
    proposal {
      id
      url
    }
  }
}

query {
  delegations {
    id
    delegator {
      id
      name
      email
    }
    delegate {
      id
      name
      email
    }
  }
}

query {
  delegation(id: 1) {
    id
    delegator {
      id
      name
      email
    }
    delegate {
      id
      name
      email
    }
  }
}
```

And [subscribe](https://github.com/absinthe-graphql/absinthe/blob/master/guides/subscriptions.md) to voting results (which will react to voting creation):

```
subscription {
  votingResultChange(proposalId:1) {
    id
    yes
    no
    proposal {
      url
    }
  }
}
```

To see this in action, open a second graphiql window and run `createVote` mutations there, and watch the subscription responses come through on the first one.

## Notes:

* No app auth, few validations, and less test coverage than ideal, to keep prototyping fast (for now). Same goes for K8s RBAC
* Auth will be implemented as a separate micro-service

## TODO

* more programmatic tests
* validations
* perf tests
* deploy to one of the cloud k8s services
* continuous deployment
* logging with ELK stack
* JS widget
* next services: authentication, notifications
* blockchain integration: Blockstack, possibly others later
