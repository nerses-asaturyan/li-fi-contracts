// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.17;

/// @title ILayerswapDepository
/// @notice Interface for the LayerswapDepository contract that forwards tokens
///         to whitelisted receiver addresses
interface ILayerswapDepository {
    /// @notice Forwards native tokens to a whitelisted receiver
    /// @param id Unique identifier for this deposit (correlates with off-chain order)
    /// @param receiver Whitelisted address to receive the funds
    function depositNative(bytes32 id, address receiver) external payable;

    /// @notice Forwards ERC20 tokens to a whitelisted receiver.
    ///         Caller must approve this contract before calling.
    /// @param id Unique identifier for this deposit (correlates with off-chain order)
    /// @param token ERC20 token address
    /// @param receiver Whitelisted address to receive the funds
    /// @param amount Amount of tokens to forward
    function depositERC20(
        bytes32 id,
        address token,
        address receiver,
        uint256 amount
    ) external;
}
