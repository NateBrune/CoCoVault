// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;
import {_ITridentRouter} from "./_ITridentRouter.sol";

/// @notice Router contract that helps in swapping across Trident pools.
interface ITridentRouter is _ITridentRouter {
    /// @dev Cached whitelisted pools.
    //mapping(address => bool) internal whitelistedPools;

    /// @notice BentoBox token vault.
    //IBentoBoxMinimal external immutable bento;

    /// @notice Master deployer.
    //IMasterDeployer external immutable masterDeployer;

    /// @notice ERC-20 token for wrapped ETH (v9).
    //address internal immutable wETH;

    /// @notice The user should use 0x0 if they want to use native currency, e.g., ETH.
    //address constant USE_NATIVE = address(0);

    /// @notice Swaps token A to token B directly. Swaps are done on `bento` tokens.
    /// @param params This includes the address of token A, pool, amount of token A to swap,
    /// minimum amount of token B after the swap and data required by the pool for the swap.
    /// @dev Ensure that the pool is trusted before calling this function. The pool can steal users' tokens.
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    /// @notice Swaps token A to token B indirectly by using multiple hops.
    /// @param params This includes the addresses of the tokens, pools, amount of token A to swap,
    /// minimum amount of token B after the swap and data required by the pools for the swaps.
    /// @dev Ensure that the pools are trusted before calling this function. The pools can steal users' tokens.
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

    /// @notice Swaps token A to token B directly. It's the same as `exactInputSingle` except
    /// it takes raw ERC-20 tokens from the users and deposits them into `bento`.
    /// @param params This includes the address of token A, pool, amount of token A to swap,
    /// minimum amount of token B after the swap and data required by the pool for the swap.
    /// @dev Ensure that the pool is trusted before calling this function. The pool can steal users' tokens.
    function exactInputSingleWithNativeToken(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    /// @notice Swaps token A to token B indirectly by using multiple hops. It's the same as `exactInput` except
    /// it takes raw ERC-20 tokens from the users and deposits them into `bento`.
    /// @param params This includes the addresses of the tokens, pools, amount of token A to swap,
    /// minimum amount of token B after the swap and data required by the pools for the swaps.
    /// @dev Ensure that the pools are trusted before calling this function. The pools can steal users' tokens.
    function exactInputWithNativeToken(ExactInputParams calldata params) external payable returns (uint256 amountOut);

    /// @notice Swaps multiple input tokens to multiple output tokens using multiple paths, in different percentages.
    /// For example, you can swap 50 DAI + 100 USDC into 60% ETH and 40% BTC.
    /// @param params This includes everything needed for the swap. Look at the `ComplexPathParams` struct for more details.
    /// @dev This function is not optimized for single swaps and should only be used in complex cases where
    /// the amounts are large enough that minimizing slippage by using multiple paths is worth the extra gas.
    function complexPath(ComplexPathParams calldata params) external payable;

    /// @notice Add liquidity to a pool.
    /// @param tokenInput Token address and amount to add as liquidity.
    /// @param pool Pool address to add liquidity to.
    /// @param minLiquidity Minimum output liquidity - caps slippage.
    /// @param data Data required by the pool to add liquidity.
    function addLiquidity(
        TokenInput[] calldata tokenInput,
        address pool,
        uint256 minLiquidity,
        bytes calldata data
    ) external payable returns (uint256 liquidity);

    /// @notice Burn liquidity tokens to get back `bento` tokens.
    /// @param pool Pool address.
    /// @param liquidity Amount of liquidity tokens to burn.
    /// @param data Data required by the pool to burn liquidity.
    /// @param minWithdrawals Minimum amount of `bento` tokens to be returned.
    /*
    function burnLiquidity(
        address pool,
        uint256 liquidity,
        bytes calldata data,
        IPool.TokenAmount[] calldata minWithdrawals
    ) external;
    */
    /// @notice Burn liquidity tokens to get back `bento` tokens.
    /// @dev The tokens are swapped automatically and the output is in a single token.
    /// @param pool Pool address.
    /// @param liquidity Amount of liquidity tokens to burn.
    /// @param data Data required by the pool to burn liquidity.
    /// @param minWithdrawal Minimum amount of tokens to be returned.
    function burnLiquiditySingle(
        address pool,
        uint256 liquidity,
        bytes calldata data,
        uint256 minWithdrawal
    ) external;

    /// @notice Recover mistakenly sent tokens.
    function sweep(
        address token,
        uint256 amount,
        address recipient,
        bool onBento
    ) external payable;

    /// @notice Unwrap this contract's `wETH` into ETH.
    function unwrapWETH(uint256 amountMinimum, address recipient) external payable;

    /// @notice Wrapper function to allow pool deployment to be batched.
    function deployPool(address factory, bytes calldata deployData) external payable returns (address);

    /// @notice Wrapper function to allow bento set master contract approval to be batched, so the first trade can happen in one transaction.
    function approveMasterContract(
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable;
}
