// SPDX-License-Identifier: BUSL-1.1
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

pragma solidity ^0.6.12;

interface IStargateGauge {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of STGs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accStargatePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accStargatePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. STGs to distribute per block.
        uint256 lastRewardBlock; // Last block number that STGs distribution occurs.
        uint256 accStargatePerShare; // Accumulated STGs per share, times 1e12. See below.
    }
    // The STG TOKEN!
    address public stargate;
    // Block number when bonus STG period ends.
    uint256 public bonusEndBlock;
    // STG tokens created per block.
    uint256 public stargatePerBlock;
    // Bonus multiplier for early stargate makers.
    uint256 public constant BONUS_MULTIPLIER = 1;

    mapping(uint256 => uint256) public lpBalances;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when STG mining starts.
    uint256 public startBlock;

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    /// @notice Withdraw without caring about rewards.
    /// @param _pid The pid specifies the pool
    function emergencyWithdraw(uint256 _pid) external;

    function pendingStargate(uint256 _pid, address _user) external view returns (uint256);

    function poolLength() external view returns (uint256);
}
