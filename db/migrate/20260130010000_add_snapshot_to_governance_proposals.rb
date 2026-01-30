# frozen_string_literal: true

# SECURITY: Adds snapshot functionality to prevent flash stake attacks
# 
# Problem: Without snapshots, users can:
# 1. See a proposal they want to influence
# 2. Borrow/buy tokens right before voting ends
# 3. Vote with borrowed power
# 4. Sell/return tokens immediately after
#
# Solution: Capture voting power at a fixed point in time (snapshot)
# and use that for all voting calculations
class AddSnapshotToGovernanceProposals < ActiveRecord::Migration[7.2]
  def change
    # Snapshot timing
    add_column :governance_proposals, :snapshot_at, :datetime
    add_column :governance_proposals, :snapshot_total_supply, :decimal, precision: 24, scale: 8
    
    # Index for efficient lookups
    add_index :governance_proposals, :snapshot_at
    
    # Add snapshot stake to votes (captured at vote time, must match snapshot)
    add_column :governance_votes, :stake_at_snapshot, :decimal, precision: 24, scale: 8
  end
end
