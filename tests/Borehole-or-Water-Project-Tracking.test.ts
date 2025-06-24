import { Clarinet, Tx, Chain, Account, types } from '@stacks/transactions';

Clarinet.test({
  name: "Ensures project creation works",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;

    let block = chain.mineBlock([
      Tx.contractCall(
        "borehole-tracker",
        "create-project",
        [
          types.ascii("Test Project"),
          types.ascii("Test Location"),
          types.uint(1000000)
        ],
        deployer.address
      )
    ]);

    block.receipts[0].result.expectOk().expectUint(1);
  },
});

Clarinet.test({
  name: "Ensures milestone creation works",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;

    let block = chain.mineBlock([
      Tx.contractCall(
        "borehole-tracker",
        "add-milestone",
        [
          types.uint(1),
          types.uint(1),
          types.ascii("First milestone"),
          types.uint(500000)
        ],
        deployer.address
      )
    ]);

    block.receipts[0].result.expectOk().expectBool(true);
  },
});
