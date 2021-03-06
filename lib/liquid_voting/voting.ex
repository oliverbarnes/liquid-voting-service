defmodule LiquidVoting.Voting do
  @moduledoc """
  The Voting context.
  """

  require OpenTelemetry.Tracer, as: Tracer

  import Ecto.Query, warn: false

  alias __MODULE__.{Participant, Vote}
  alias LiquidVoting.{Delegations, Repo}
  alias LiquidVoting.Delegations.Delegation

  @doc """
  Creates a vote, and deletes a voter's previous
  delegation if present

  ## Examples

      iex> create_vote(%{field: value})
      {:ok, %Vote{}}

      iex> create_vote(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_vote(attrs \\ %{}) do
    Tracer.with_span "#{__MODULE__} #{inspect(__ENV__.function)}" do
      Tracer.set_attributes([
        {:request_id, Logger.metadata()[:request_id]},
        {:params,
         [
           {:organization_id, attrs[:organization_id]},
           {:participant_email, attrs[:participant_email]},
           {:proposal_url, attrs[:proposal_url]},
           {:voting_method, attrs[:voting_method]},
           {:yes, attrs[:yes]}
         ]}
      ])

      Repo.transaction(fn ->
        %Vote{}
        |> Vote.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, vote} ->
            if delegation =
                 Repo.get_by(Delegation,
                   delegator_id: attrs[:participant_id],
                   organization_id: attrs[:organization_id]
                 ) do
              case Delegations.delete_delegation(delegation) do
                {:ok, _delegation} ->
                  vote
                  |> Repo.preload([:voting_method])

                {:error, changeset} ->
                  Repo.rollback(changeset)
              end
            else
              vote
              |> Repo.preload([:voting_method])
            end

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    end
  end

  @doc """
  Returns the list of votes for an organization id.

  ## Examples

      iex> list_votes("a6158b19-6bf6-4457-9d13-ef8b141611b4")
      [%Vote{}, ...]

  """
  def list_votes(organization_id) do
    Tracer.with_span "#{__MODULE__} #{inspect(__ENV__.function)}" do
      Tracer.set_attributes([
        {:request_id, Logger.metadata()[:request_id]},
        {:params, [{:organization_id, organization_id}]}
      ])

      Vote
      |> where(organization_id: ^organization_id)
      |> Repo.all()
      |> Repo.preload([:participant])
      |> Repo.preload([:voting_method])
    end
  end

  @doc """
  Returns the list of votes for a voting_method_id, proposal_url and organization id

  ## Examples

      iex> list_votes_by_proposal(
        "61dbd65c-2c1f-4c29-819c-bbd27112a868",
        "https://docs.google.com/document/d/someid",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4")
      [%Vote{}, ...]

  """
  def list_votes_by_proposal(voting_method_id, proposal_url, organization_id) do
    Tracer.with_span "#{__MODULE__} #{inspect(__ENV__.function)}" do
      Tracer.set_attributes([
        {:request_id, Logger.metadata()[:request_id]},
        {:params,
         [
           {:organization_id, organization_id},
           {:proposal_url, proposal_url},
           {:voting_method_id, voting_method_id}
         ]}
      ])

      Vote
      |> where(
        voting_method_id: ^voting_method_id,
        proposal_url: ^proposal_url,
        organization_id: ^organization_id
      )
      |> Repo.all()
      |> Repo.preload([:participant])
      |> Repo.preload([:voting_method])
    end
  end

  @doc """
  Returns the list of votes for a participant id and organization id

  ## Examples

      iex> list_votes_by_participant(
        "cc1e2ea3-317e-4f40-97b4-06db6e48cd05",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4"
        )
      [%Vote{}, ...]

  """
  def list_votes_by_participant(participant_id, organization_id) do
    Vote
    |> where(participant_id: ^participant_id, organization_id: ^organization_id)
    |> Repo.all()
    |> Repo.preload([:participant])
    |> Repo.preload([:voting_method])
  end

  @doc """
  Gets a single vote by id and organization id

  Raises `Ecto.NoResultsError` if the Vote does not exist.

  ## Examples

      iex> get_vote!(
        "61dbd65c-2c1f-4c29-819c-bbd27112a868",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4"
        )
      %Vote{}

      iex> get_vote!(456)
      ** (Ecto.NoResultsError)

  """
  def get_vote!(id, organization_id) do
    Vote
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload([:participant])
    |> Repo.preload([:voting_method])
  end

  @doc """
  Gets a single vote by participant email, voting_method_id, proposal_url and organization id

  ## Examples

      iex> get_vote!(
              "alice@email.com",
              "61dbd65c-2c1f-4c29-819c-bbd27112a868",
              "https://proposals.net/2",
              "a6158b19-6bf6-4457-9d13-ef8b141611b4"
            )
      %Vote{}

      iex> get_vote!(
              "hasno@votes.com",
              "61dbd65c-2c1f-4c29-819c-bbd27112a868",
              "https://proposals.net/2",
              "a6158b19-6bf6-4457-9d13-ef8b141611b4"
            )
      ** (Ecto.NoResultsError)

  """
  def get_vote!(email, voting_method_id, proposal_url, organization_id) do
    participant = get_participant_by_email!(email, organization_id)

    Vote
    |> Repo.get_by!(
      organization_id: organization_id,
      participant_id: participant.id,
      proposal_url: proposal_url,
      voting_method_id: voting_method_id
    )
    |> Repo.preload([:participant])
    |> Repo.preload([:voting_method])
  end

  @doc """
  Gets a single vote by participant id, voting_method_id and proposal_url
  ## Examples

      iex> get_vote_by_participant_id(
        "61dbd65c-2c1f-4c29-819c-bbd27112a868",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4",
        "https://proposals.net/2",
        "61dbd65c-2c1f-4c29-819c-bbd27112a868"
        )
      => %Vote{}

      iex> get_vote_by_participant_id(
        "61dbd65c-2c1f-4c29-819c-bbd27112a868",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4",
        "https://proposals.com/non-existant-proposal",
        "61dbd65c-2c1f-4c29-819c-bbd27112a868"
        )
      => nil
  """
  def get_vote_by_participant_id(participant_id, voting_method_id, proposal_url, organization_id) do
    Vote
    |> where(
      organization_id: ^organization_id,
      participant_id: ^participant_id,
      proposal_url: ^proposal_url,
      voting_method_id: ^voting_method_id
    )
    |> Repo.one()
    |> Repo.preload([:participant])
    |> Repo.preload([:voting_method])
  end

  # Just for seeding
  def create_vote!(attrs \\ %{}) do
    %Vote{}
    |> Vote.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Updates a vote.

  ## Examples

      iex> update_vote(vote, %{field: new_value})
      {:ok, %Vote{}}

      iex> update_vote(vote, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_vote(%Vote{} = vote, attrs) do
    vote
    |> Vote.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Vote.

  ## Examples

      iex> delete_vote(vote)
      {:ok, %Vote{}}

      iex> delete_vote(vote)
      {:error, %Ecto.Changeset{}}

  """
  def delete_vote(%Vote{} = vote), do: Repo.delete(vote)

  @doc """
  Deletes a Vote.

  ## Examples

      iex> delete_vote!(vote)
      %Vote{}

      iex> delete_vote!(vote)
      Ecto.*Error

  """
  def delete_vote!(%Vote{} = vote), do: Repo.delete!(vote)

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking vote changes.

  ## Examples

      iex> change_vote(vote)
      %Ecto.Changeset{source: %Vote{}}

  """
  def change_vote(%Vote{} = vote), do: Vote.changeset(vote, %{})

  @doc """
  Returns the list of participants for an organization id

  ## Examples

      iex> list_participants("a6158b19-6bf6-4457-9d13-ef8b141611b4")
      [%Participant{}, ...]

  """
  def list_participants(organization_id) do
    Participant
    |> where(organization_id: ^organization_id)
    |> Repo.all()
  end

  @doc """
  Gets a single participant for an organization id

  Raises `Ecto.NoResultsError` if the Participant does not exist.

  ## Examples

      iex> get_participant!(
        "c508af54-a6dc-44da-ab8d-ef335bfd3cec",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4"
        )
      %Participant{}

      iex> get_participant!(
        "076a5a58-1bfa-4139-8d12-5e2ae0309866",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4"
        )
      ** (Ecto.NoResultsError)

  """
  def get_participant!(id, organization_id),
    do: Repo.get_by!(Participant, id: id, organization_id: organization_id)

  @doc """
  Gets a single participant for an organization id by their email

  Returns nil if the Participant does not exist.

  ## Examples

      iex> get_participant_by_email(
        "existing@email.com",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4"
        )
      %Participant{}

      iex> get_participant_by_email(
        "unregistered@email.com",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4"
        )
      nil

  """
  def get_participant_by_email(email, organization_id),
    do: Repo.get_by(Participant, email: email, organization_id: organization_id)

  @doc """
  Gets a single participant for an organization id by their email

  Raises `Ecto.NoResultsError` if the Participant does not exist.

  ## Examples

      iex> get_participant_by_email!(
        "existing@email.com",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4"
        )
      %Participant{}

      iex> get_participant_by_email!(
        "unregistered@email.com",
        "a6158b19-6bf6-4457-9d13-ef8b141611b4"
        )
      ** (Ecto.NoResultsError)

  """
  def get_participant_by_email!(email, organization_id),
    do: Repo.get_by!(Participant, email: email, organization_id: organization_id)

  @doc """
  Creates a participant.

  ## Examples

      iex> create_participant(%{field: value})
      {:ok, %Participant{}}

      iex> create_participant(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_participant(attrs \\ %{}) do
    %Participant{}
    |> Participant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a participant.

  ## Examples

      iex> create_participant(%{field: value})
      %Participant{}

      iex> create_participant(%{field: bad_value})
      Ecto.*Error

  """
  def create_participant!(attrs \\ %{}) do
    %Participant{}
    |> Participant.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Upserts a participant (updates or inserts).

  ## Examples

      iex> upsert_participant(%{field: value})
      {:ok, %Participant{}}

      iex> upsert_participant(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  def upsert_participant(attrs \\ %{}) do
    Tracer.with_span "#{__MODULE__} #{inspect(__ENV__.function)}" do
      Tracer.set_attributes([
        {:request_id, Logger.metadata()[:request_id]},
        {:params,
         [
           {:organization_id, attrs[:organization_id]},
           {:email, attrs[:email]},
           {:name, attrs[:name]}
         ]}
      ])

      %Participant{}
      |> Participant.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace_all_except, [:id]},
        conflict_target: [:organization_id, :email],
        returning: true
      )
    end
  end

  @doc """
  Updates a participant.

  ## Examples

      iex> update_participant(participant, %{field: new_value})
      {:ok, %Participant{}}

      iex> update_participant(participant, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_participant(%Participant{} = participant, attrs) do
    participant
    |> Participant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Participant.

  ## Examples

      iex> delete_participant(participant)
      {:ok, %Participant{}}

      iex> delete_participant(participant)
      {:error, %Ecto.Changeset{}}

  """
  def delete_participant(%Participant{} = participant), do: Repo.delete(participant)

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking participant changes.

  ## Examples

      iex> change_participant(participant)
      %Ecto.Changeset{source: %Participant{}}

  """
  def change_participant(%Participant{} = participant),
    do: Participant.changeset(participant, %{})
end
