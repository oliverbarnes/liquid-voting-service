defmodule LiquidVotingWeb.Resolvers.Delegations do
  alias LiquidVoting.{Delegations, Voting, VotingResults}
  alias LiquidVotingWeb.Schema.ChangesetErrors

  def delegations(_, _, %{context: %{organization_uuid: organization_uuid}}),
    do: {:ok, Delegations.list_delegations(organization_uuid)}

  def delegation(_, %{id: id}, %{context: %{organization_uuid: organization_uuid}}),
    do: {:ok, Delegations.get_delegation!(id, organization_uuid)}

  # Will add participants to the db if they don't exist yet, or fetch them if they do. 
  # Their ids are used for delegator_id and delegate_id when inserting the delegation
  # with create_delegation_with_valid_arguments/1
  # TODO: break up into smaller functions. 
  def create_delegation(
        _,
        %{delegator_email: delegator_email, delegate_email: delegate_email} = args,
        %{context: %{organization_uuid: organization_uuid}}
      ) do
    case Voting.upsert_participant(%{email: delegator_email, organization_uuid: organization_uuid}) do
      {:error, changeset} ->
        {:error,
         message: "Could not create delegation with given email",
         details: ChangesetErrors.error_details(changeset)}

      {:ok, delegator} ->
        args =
          args
          |> Map.put(:delegator_id, delegator.id)
          |> Map.put(:organization_uuid, organization_uuid)

        case Voting.upsert_participant(%{
               email: delegate_email,
               organization_uuid: organization_uuid
             }) do
          {:error, changeset} ->
            {:error,
             message: "Could not create delegation with given email",
             details: ChangesetErrors.error_details(changeset)}

          {:ok, delegate} ->
            args
            |> Map.put(:delegate_id, delegate.id)
            |> create_delegation_with_valid_arguments()
        end
    end
  end

  def create_delegation(_, %{} = args, %{context: %{organization_uuid: organization_uuid}}) do
    args
    |> Map.put(:organization_uuid, organization_uuid)
    |> create_delegation_with_valid_arguments()
  end

  def create_delegation_with_valid_arguments(args) do
    case Delegations.create_delegation(args) do
      {:error, changeset} ->
        {:error,
         message: "Could not create delegation", details: ChangesetErrors.error_details(changeset)}

      {:ok, delegation} ->
        {:ok, delegation}
    end
  end

  ## Delete proposal-specific delegations
  def delete_delegation(
        _,
        %{
          delegator_email: delegator_email,
          delegate_email: delegate_email,
          proposal_url: proposal_url
        },
        %{context: %{organization_uuid: organization_uuid}}
      ) do
    deleted_delegation =
      delegator_email
      |> Delegations.get_delegation!(delegate_email, proposal_url, organization_uuid)
      |> Delegations.delete_delegation!()

    VotingResults.publish_voting_result_change(proposal_url, organization_uuid)
    {:ok, deleted_delegation}
  rescue
    Ecto.NoResultsError -> {:error, message: "No delegation found to delete"}
  end

  ## Delete global delegations
  def delete_delegation(_, %{delegator_email: delegator_email, delegate_email: delegate_email}, %{
        context: %{organization_uuid: organization_uuid}
      }) do
    deleted_delegation =
      delegator_email
      |> Delegations.get_delegation!(delegate_email, organization_uuid)
      |> Delegations.delete_delegation!()

    # VotingResults.publish_voting_result_change(proposal_url, organization_uuid)
    {:ok, deleted_delegation}
  rescue
    Ecto.NoResultsError -> {:error, message: "No delegation found to delete"}
  end
end
