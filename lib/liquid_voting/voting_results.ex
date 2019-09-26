defmodule LiquidVoting.VotingResults do
  @moduledoc """
  The VotingResults context.
  """

  import Ecto.Query, warn: false
  alias LiquidVoting.Repo
  alias LiquidVoting.Voting
  alias LiquidVoting.VotingResults.Result

  @doc """
  Creates or updates voting result based on votes
  given to a proposal

  ## Examples

      iex> calculate_result!(proposal)
      %Result{}

  """
  def calculate_result!(proposal) do
    proposal = Repo.preload(proposal, :votes)

    attrs = %{
      yes: 0,
      no: 0,
      proposal_id: proposal.id
    }

    attrs =
      Enum.reduce proposal.votes, attrs, fn (vote, attrs) ->
        {:ok, vote} = Voting.update_vote_weight(vote)

        if vote.yes do
          Map.update!(attrs, :yes, &(&1 + vote.weight))
        else
          Map.update!(attrs, :no, &(&1 + vote.weight))
        end
      end

    %Result{}
    |> Result.changeset(attrs)
    |> Repo.insert!
  end

  def publish_voting_result_change(proposal_id) do
    result =
      proposal_id
      |> Voting.get_proposal!
      |> calculate_result!

    Absinthe.Subscription.publish(
      LiquidVotingWeb.Endpoint,
      result,
      voting_result_change: proposal_id
    )
  end

  @doc """
  Returns the list of results.

  ## Examples

      iex> list_results()
      [%Result{}, ...]

  """
  def list_results do
    Repo.all(Result)
  end

  @doc """
  Gets a single result.

  Raises `Ecto.NoResultsError` if the Result does not exist.

  ## Examples

      iex> get_result!(123)
      %Result{}

      iex> get_result!(456)
      ** (Ecto.NoResultsError)

  """
  def get_result!(id), do: Repo.get!(Result, id)

  @doc """
  Creates a result.

  ## Examples

      iex> create_result(%{field: value})
      {:ok, %Result{}}

      iex> create_result(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_result(attrs \\ %{}) do
    %Result{}
    |> Result.changeset(attrs)
    |> Repo.insert()
  end

  def create_result!(attrs \\ %{}) do
    %Result{}
    |> Result.changeset(attrs)
    |> Repo.insert!
  end
end