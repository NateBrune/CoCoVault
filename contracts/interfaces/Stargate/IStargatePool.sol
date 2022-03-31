// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.12;

interface IStargatePool {
    function amountLPtoLD(uint256 _amountLP) external view returns (uint256);
}
