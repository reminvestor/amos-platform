import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { AmosGovernance } from "../target/types/amos_governance";
import { 
  createMint, 
  getOrCreateAssociatedTokenAccount,
  mintTo,
  TOKEN_PROGRAM_ID 
} from "@solana/spl-token";
import { expect } from "chai";

describe("amos_governance", () => {
  // Configure the client to use the local cluster
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace.AmosGovernance as Program<AmosGovernance>;
  
  let amosMint: anchor.web3.PublicKey;
  let authority: anchor.web3.Keypair;
  let oracleAuthority: anchor.web3.Keypair;
  let builder: anchor.web3.Keypair;
  let voter: anchor.web3.Keypair;
  let governanceConfig: anchor.web3.PublicKey;
  let treasury: anchor.web3.PublicKey;

  before(async () => {
    authority = anchor.web3.Keypair.generate();
    oracleAuthority = anchor.web3.Keypair.generate();
    builder = anchor.web3.Keypair.generate();
    voter = anchor.web3.Keypair.generate();

    // Airdrop SOL to all accounts
    const airdropAmount = 10 * anchor.web3.LAMPORTS_PER_SOL;
    for (const keypair of [authority, oracleAuthority, builder, voter]) {
      const sig = await provider.connection.requestAirdrop(
        keypair.publicKey, 
        airdropAmount
      );
      await provider.connection.confirmTransaction(sig);
    }

    // Create AMOS mint
    amosMint = await createMint(
      provider.connection,
      authority,
      authority.publicKey,
      null,
      9 // 9 decimals like SOL
    );

    // Derive PDAs
    [governanceConfig] = anchor.web3.PublicKey.findProgramAddressSync(
      [Buffer.from("governance_config")],
      program.programId
    );

    [treasury] = anchor.web3.PublicKey.findProgramAddressSync(
      [Buffer.from("treasury")],
      program.programId
    );
  });

  describe("initialize_governance", () => {
    it("initializes governance config with correct parameters", async () => {
      const config = {
        mrrWeightBps: 6000,       // 60%
        communityWeightBps: 4000, // 40%
        recencyHalfLifeDays: 30,
        minBenchmarkScore: 7000,  // 70%
        minAbImprovementBps: 500, // 5%
        minFeedbackRatioBps: 7000, // 70%
        stewardQuorum: 3,
        bountyCompletionBps: 4000, // 40%
        bountyAbSuccessBps: 3000,  // 30%
        bountyStableMergeBps: 3000, // 30%
        researchStipendBps: 2000,  // 20%
        researchSuccessMultiplierBps: 4000, // 400%
      };

      await program.methods
        .initializeGovernance(config)
        .accounts({
          governanceConfig,
          amosMint,
          treasury,
          authority: authority.publicKey,
          oracleAuthority: oracleAuthority.publicKey,
          systemProgram: anchor.web3.SystemProgram.programId,
          tokenProgram: TOKEN_PROGRAM_ID,
          rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
        .signers([authority])
        .rpc();

      const governanceAccount = await program.account.governanceConfig.fetch(governanceConfig);
      
      expect(governanceAccount.authority.toString()).to.equal(authority.publicKey.toString());
      expect(governanceAccount.oracleAuthority.toString()).to.equal(oracleAuthority.publicKey.toString());
      expect(governanceAccount.amosMint.toString()).to.equal(amosMint.toString());
      expect(governanceAccount.totalProposals.toNumber()).to.equal(0);
      expect(governanceAccount.params.mrrWeightBps).to.equal(6000);
    });
  });

  describe("submit_feature_proposal", () => {
    it("creates a new feature proposal", async () => {
      const [proposalPda] = anchor.web3.PublicKey.findProgramAddressSync(
        [Buffer.from("feature_proposal"), new anchor.BN(0).toArrayLike(Buffer, "le", 8)],
        program.programId
      );

      await program.methods
        .submitFeatureProposal(
          "Add Stripe Charges Integration",
          "Implement list_charges operation for Stripe integration",
          new anchor.BN(1000 * 10**9), // 1000 AMOS bounty
          [] // No customer requests linked
        )
        .accounts({
          governanceConfig,
          proposal: proposalPda,
          proposer: builder.publicKey,
          systemProgram: anchor.web3.SystemProgram.programId,
        })
        .signers([builder])
        .rpc();

      const proposal = await program.account.featureProposal.fetch(proposalPda);
      
      expect(proposal.id.toNumber()).to.equal(0);
      expect(proposal.proposer.toString()).to.equal(builder.publicKey.toString());
      expect(proposal.status).to.deep.equal({ submitted: {} });
      expect(proposal.bountyAmount.toNumber()).to.equal(1000 * 10**9);
    });
  });

  describe("vote_for_feature", () => {
    it("allows token holders to vote on proposals", async () => {
      // Mint some AMOS to voter
      const voterTokenAccount = await getOrCreateAssociatedTokenAccount(
        provider.connection,
        voter,
        amosMint,
        voter.publicKey
      );

      await mintTo(
        provider.connection,
        authority,
        amosMint,
        voterTokenAccount.address,
        authority,
        100 * 10**9 // 100 AMOS
      );

      const [proposalPda] = anchor.web3.PublicKey.findProgramAddressSync(
        [Buffer.from("feature_proposal"), new anchor.BN(0).toArrayLike(Buffer, "le", 8)],
        program.programId
      );

      const [voteRecordPda] = anchor.web3.PublicKey.findProgramAddressSync(
        [
          Buffer.from("vote"), 
          new anchor.BN(0).toArrayLike(Buffer, "le", 8),
          voter.publicKey.toBuffer()
        ],
        program.programId
      );

      await program.methods
        .voteForFeature(
          new anchor.BN(0), // proposal ID
          new anchor.BN(50 * 10**9) // 50 AMOS vote
        )
        .accounts({
          governanceConfig,
          proposal: proposalPda,
          voteRecord: voteRecordPda,
          voterTokenAccount: voterTokenAccount.address,
          voteEscrow: treasury,
          voter: voter.publicKey,
          tokenProgram: TOKEN_PROGRAM_ID,
          systemProgram: anchor.web3.SystemProgram.programId,
        })
        .signers([voter])
        .rpc();

      const voteRecord = await program.account.voteRecord.fetch(voteRecordPda);
      expect(voteRecord.voteAmount.toNumber()).to.equal(50 * 10**9);
      expect(voteRecord.voter.toString()).to.equal(voter.publicKey.toString());

      const proposal = await program.account.featureProposal.fetch(proposalPda);
      expect(proposal.communityVotes.toNumber()).to.equal(50 * 10**9);
    });
  });

  describe("quality gates", () => {
    it("oracle can report benchmark results", async () => {
      const [proposalPda] = anchor.web3.PublicKey.findProgramAddressSync(
        [Buffer.from("feature_proposal"), new anchor.BN(0).toArrayLike(Buffer, "le", 8)],
        program.programId
      );

      // First update status to InReview
      await program.methods
        .updateProposalStatus(new anchor.BN(0), { inReview: {} })
        .accounts({
          governanceConfig,
          proposal: proposalPda,
          oracleAuthority: oracleAuthority.publicKey,
        })
        .signers([oracleAuthority])
        .rpc();

      // Report benchmark result
      const evidenceHash = Buffer.alloc(32);
      evidenceHash.fill(0xAB);

      await program.methods
        .reportBenchmarkResult(
          new anchor.BN(0),
          true, // passed
          8500, // 85% score
          Array.from(evidenceHash) as any
        )
        .accounts({
          governanceConfig,
          proposal: proposalPda,
          oracleAuthority: oracleAuthority.publicKey,
        })
        .signers([oracleAuthority])
        .rpc();

      const proposal = await program.account.featureProposal.fetch(proposalPda);
      expect(proposal.gates.benchmark.evaluated).to.be.true;
      expect(proposal.gates.benchmark.passed).to.be.true;
      expect(proposal.gates.benchmark.score).to.equal(8500);
      expect(proposal.status).to.deep.equal({ inAbTest: {} });
    });
  });

  describe("calculate_priority", () => {
    it("calculates priority score correctly", async () => {
      const [proposalPda] = anchor.web3.PublicKey.findProgramAddressSync(
        [Buffer.from("feature_proposal"), new anchor.BN(0).toArrayLike(Buffer, "le", 8)],
        program.programId
      );

      const priority = await program.methods
        .calculatePriority(new anchor.BN(0))
        .accounts({
          governanceConfig,
          proposal: proposalPda,
        })
        .view();

      // Priority should be > 0 due to community votes and recency bonus
      expect(priority.toNumber()).to.be.greaterThan(0);
      console.log(`Calculated priority: ${priority.toNumber()}`);
    });
  });
});
