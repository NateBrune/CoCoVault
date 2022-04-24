// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.12;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStargatePool is IERC20 {
    function amountLPtoLD(uint256 _amountLP) external view returns (uint256);
}
