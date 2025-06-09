# Dragonswap Token Release Kit
A set of contracts related to the Dragonswap token release.

Consists of the Airdrop contract and Staker contract.

Initial tokens will be released through the Airdrop contract, once unlocked they can be staked in order to generate earnings.

## Airdrop & Staker
The `Airdrop` contract serves to safely distribute token portions.

An `Airdrop` contract instance can only distribute portions of a single token.

The distribution is done by setting the unlock timestamps for waves of portions and depositing a sufficient amount of tokens by the `Owner`.

Unlock timestamps can be added and/or changed while the contract lock mechanism is inactive. Once locked, all settings except fee modification are frozen.

Unlock timestamps must maintain an ascending order at all times.

Two important authorities on the Airdrop contract are `Owner` and `Signer` wallets.

Unclaimed tokens can be withdrawn by the `Owner` after the `cleanupBuffer` time passes after the final unlock.

The `Owner` has no deadline to sweep the unclaimed tokens.

Portion values are manually set for each wave for each user. And can be changed (until the lock activates).

User is able to withdraw tokens to wallet, or directly to the staker contract.

Withdrawal requires a signature from a protected wallet `Signer`, which provides an extra layer of security.

Direct withdrawals (to the user's wallet) are subject to a penalty, which is adjustable on the `Staker` contract.

Token amount taken as a penalty is directly transferred to treasury, with a purpose of further distribution to users.

Staker contract is also able to receive stake tokens of external origin (outside of `Airdrop`, someone can buy tokens and stake them).

Accounts can make deposits one for the other, but only the account which owns the stake can earn rewards and withdraw the stake.

Stakes can be locked on deposit, but do not have to be.

Withdrawal of a stake which was not previously locked will be a subject to the penalty (the same one as for the direct wallet withdrawal from the `Airdrop`).

Percent applied as a penalty is set on the `Staker` contract and inherited by the `Airdrop`, making sure they're always aligned.

Locktimespan (length of a stake lock) is equal for each and every stake, and there are no options to choose from (only lock or do not lock).

Once stake is unlocked, it will continue to earn rewards but will become withdrawable and also excluded from paying the withdrawal penalty.
Stake which was not locked is withdrawable since the beginning and will be a subject to the withdrawal fee.

Staker can distribute `n` tokens to users, where `n` is the maximum amount of reward tokens compatible with the computational limit.

Users have a limited amount of stakes. Stakes are not removed from the structures but only marked once claimed, so for the lifetime of the staker contract, each wallet has a maximum threshold of stakes that it can have. (This is a subject to change, with proper checks we will make sure if this borderline is needed or not. Since the flow mostly works atomically we might not need the limit.)

Reward tokens can be added and removed at any point in time. Leftovers of removed reward tokens can be swept by the `Owner`.

User can see the accumulated earnings through the external view functions. (Currently working per user stake, per reward token, we might extend the initial views, but this seems alright too.)

`Owner` reward deposit to the `Airdrop` contract must be done through a function call, while on the `Staker` side, reward tokens must be simply sent to the contract.

User is able to operate over a multitude of stakes in a single call: withdraw, claim earnings and emergency withdraw.

While the ordinary withdraw claims earnings by default, emergency withdraw will leave earnings in the contract.

Earnings claim sends all accumulated earnings for the selection of stakes to the user's wallet.
