// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "../BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

// Import interfaces for many popular DeFi projects, or add your own!
import "../interfaces/Stargate/IStargateGauge.sol";
import "../interfaces/Stargate/IStargatePool.sol";
import "../interfaces/Stargate/IStargateRouter.sol";
import "../interfaces/Uni/IUniswapV2Router02.sol";

contract Stargazer is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IStargateGauge public gauge;
    IStargatePool public pool;
    IStargateRouter public starRouter;
    IUniswapV2Router02 private currentRouter; //uni v2 forks only
    address private tradingToken;
    address private stg;
    address private nativeToken;
    uint16 private pid;
    uint256 private minWant;
    uint256 private minStgToSell;
    uint256 private maxSingleInvest;

    constructor(
        address _vault,
        IStargateGauge _gauge,
        IStargatePool _pool,
        IStargateRouter _starRouter,
        IUniswapV2Router02 _currentRouter,
        address _tradingToken,
        address _nativeToken,
        address _stg,
        uint16 _pid
    ) public BaseStrategy(_vault) {
        // You can set these parameters on deployment to whatever you want
        // maxReportDelay = 6300;
        // profitFactor = 100;
        // debtThreshold = 0;
        // TODO: approvals for these
        gauge = _gauge;
        pool = _pool;
        starRouter = _starRouter;
        currentRouter = _currentRouter;
        tradingToken = _tradingToken;
        nativeToken = _nativeToken;
        stg = _stg;
        pid = _pid;
        minWant = 0; // TODO: set minWant
        maxSingleInvest = 100000000000000000000; // TODO: set maxSingleInvest
        minStgToSell = 1;
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "Stargazer";
    }

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    function getGaugeBalanceInWant() internal view returns (uint256) {
        //mapping(address => UserInfo) storage info = gauge.userInfo[pid];

        (uint256 _amount, uint256 _rewardDebt) = gauge.userInfo(pid, address(this));
        //(uint256 _amount, uint256 _rewardDebt) = info[address];
        uint256 lp = _amount;
        return pool.amountLPtoLD(lp);
    }

    //sell joe function
    function balanceOfToken(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 bal = getGaugeBalanceInWant();
        //uint256 vault_bal = want.balanceOf(address(vault));
        //uint256 total = bal.add(vault_bal);
        return bal.add(balanceOfToken(address(want)));
    }

    function getTokenOutPathV2(address _tokenIn, address _tokenOut) internal view returns (address[] memory _path) {
        // expect stg in, tokenOut make not be liquid trading partner. max path size is 3.

        bool isLiquid = _tokenOut == tradingToken;
        _path = new address[](isLiquid ? 2 : 3);
        _path[0] = _tokenIn;

        if (isLiquid) {
            _path[1] = tradingToken;
        } else {
            _path[1] = tradingToken;
            _path[2] = _tokenOut;
        }
    }

    function _disposeOfStg() internal {
        uint256 _amountIn = balanceOfToken(stg);
        if (_amountIn < minStgToSell) {
            return;
        }
        IERC20(stg).approve(address(currentRouter), _amountIn);
        currentRouter.swapExactTokensForTokens(_amountIn, 0, getTokenOutPathV2(stg, address(want)), address(this), now);
    }

    function harvester() public {
        // claim STG
        gauge.deposit(pid, 0);

        _disposeOfStg();
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        _profit = 0;
        _loss = 0; // for clarity. also reduces bytesize
        _debtPayment = 0;

        //claim rewards
        harvester();

        //get base want balance
        uint256 wantBalance = want.balanceOf(address(this));

        uint256 balance = estimatedTotalAssets();

        //get amount given to strat by vault
        uint256 debt = vault.strategies(address(this)).totalDebt;

        //Check to see if there is nothing invested
        if (balance == 0 && debt == 0) {
            return (_profit, _loss, _debtPayment);
        }

        //Balance - Total Debt is profit
        if (balance > debt) {
            _profit = balance.sub(debt);

            uint256 needed = _profit.add(_debtOutstanding);
            if (needed > wantBalance) {
                needed = needed.sub(wantBalance);
                withdrawSome(needed);

                wantBalance = balanceOfToken(address(want));

                if (wantBalance < needed) {
                    if (_profit > wantBalance) {
                        _profit = wantBalance;
                        _debtPayment = 0;
                    } else {
                        _debtPayment = Math.min(wantBalance.sub(_profit), _debtOutstanding);
                    }
                } else {
                    _debtPayment = _debtOutstanding;
                }
            } else {
                _debtPayment = _debtOutstanding;
            }
        } else {
            _loss = debt.sub(balance);
            if (_debtOutstanding > wantBalance) {
                withdrawSome(_debtOutstanding.sub(wantBalance));
                wantBalance = balanceOfToken(address(want));
            }

            _debtPayment = Math.min(wantBalance, _debtOutstanding);
        }
    }

    function withdrawSome(uint256 _amount) internal {
        if (_amount < minWant) {
            return;
        }

        // Decimals of _amount token must be 6 eg USDC/USDT
        uint256 price = pool.amountLPtoLD(100000);
        uint256 cost = _amount.div(price);

        gauge.withdraw(pid, cost);
        uint256 bal = pool.balanceOf(address(this));
        pool.approve(address(starRouter), bal);
        starRouter.instantRedeemLocal(pid, cost, address(this));
    }

    function depositSome(uint256 _amount) internal {
        if (_amount < minWant) {
            return;
        }
        IERC20(tradingToken).approve(address(starRouter), _amount);
        starRouter.addLiquidity(pid, _amount, address(this));
        uint256 bal = pool.balanceOf(address(this));
        pool.approve(address(gauge), bal);
        gauge.deposit(pid, bal);
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        //we are spending all our cash unless we have debt outstanding
        uint256 _wantBal = balanceOfToken(address(want));
        if (_wantBal < _debtOutstanding) {
            withdrawSome(_debtOutstanding.sub(_wantBal));
            return;
        }

        // send all of our want tokens to be deposited
        //uint256 newDebt = _debtOutstanding.div((10**12));
        uint256 toInvest = _wantBal.sub(_debtOutstanding);

        uint256 _wantToInvest = Math.min(toInvest, maxSingleInvest);
        // deposit and stake
        depositSome(_wantToInvest);
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        // TODO: Do stuff here to free up to `_amountNeeded` from all positions back into `want`
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`

        uint256 totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            _liquidatedAmount = totalAssets;
            _loss = _amountNeeded.sub(totalAssets);
        }
        _liquidatedAmount = _amountNeeded;
        if (_liquidatedAmount > 0) {
            withdrawSome(_liquidatedAmount);
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        // TODO: Liquidate all positions and return the amount freed.
        harvester();
        uint256 balance = getGaugeBalanceInWant();
        withdrawSome(balance);
        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens() internal view override returns (address[] memory) {
        address[] memory protected = new address[](3);
        protected[0] = address(pool);
        protected[1] = address(stg);
        //      return protected;
    }

    function priceCheck(
        address start,
        address end,
        uint256 _amount
    ) public view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        if (start == end) {
            return _amount;
        }

        uint256[] memory amounts = currentRouter.getAmountsOut(_amount, getTokenOutPathV2(start, end));

        return amounts[amounts.length - 1];
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei) public view virtual override returns (uint256) {
        // TODO create an accurate price oracle
        return priceCheck(nativeToken, address(want), _amtInWei);
        //return _amtInWei;
    }
}
