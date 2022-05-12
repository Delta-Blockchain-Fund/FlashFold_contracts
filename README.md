# AAVE_FOLD_UNFOLD

Smart contracts to Fold and Unfold positions on AAVE in a single transaction without
going through the tedious process of making multiple transactions to
Deposit->Borrow->Deposit
The contracts utilizes AAVE Flash loans to simplify the process in a single transaction

## Deployment

• Install dependencies

```bash
  npm install
```

• Make a .env file in project root and add all necessary variables mentioned in .env.example

• Deploy contracts

```bash
  npx hardhat run --network <network-name> scripts/deploy.ts
```

AAVE contracts are deployed on ropsten and kovan, so use either of the two testnets.

• CLI will print the deployed address of smart contract
