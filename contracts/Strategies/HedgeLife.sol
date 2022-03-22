// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "../BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/Uni/IUniswapV2Router02.sol";
import "../interfaces/dHedge/IdHedgePool.sol";
import "../interfaces/IERC20Extended.sol";

contract HedgeLife is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IdHedgePool public dHEDGEStableYield;
    IUniswapV2Router02 public router;
    IERC20Extended hedgeToken;
    address public constant wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address public constant usdc = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address public constant weth = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    uint256 minhedgeToSell;

    //for calculating profit without harvest
    uint256 lastPPS = 0;
    uint256 lastShares = 0;
    uint256 minWant = 0;

    constructor(
        address _vault,
        address _router,
        address _rewardToken
    ) public BaseStrategy(_vault) {
        // Setup Uniswap approvals
        _initializeThis(_vault, _router, _rewardToken);
    }

    function _initializeThis(
        address _vault, // TODO: verify vault == want and remove _vault from constructor
        address _router,
        address _rewardToken
    ) internal {
        dHEDGEStableYield = IdHedgePool(_vault);
        hedgeToken = IERC20Extended(_rewardToken);
        router = IUniswapV2Router02(_router);
        require(IERC20Extended(address(want)).decimals() <= 18); // dev: want not supported

        //pre-set approvals
        approveTokenMax(address(hedgeToken), address(router));
        approveTokenMax(usdc, address(hedgeToken));

        // set minWant to 1 want
        minWant = uint256(uint256(10)**uint256((IERC20Extended(address(want))).decimals())).div(1);
        // set minhedgeToSell to 1 DHT.
        minhedgeToSell = uint256(uint256(10)**uint256((IERC20Extended(address(dHEDGEStableYield))).decimals())).div(1);
    }

    function approveTokenMax(address token, address spender) internal {
        IERC20(token).safeApprove(spender, type(uint256).max);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "HedgeLife";
    }

    function changeVault(address _vault) public onlyStrategist {
        require(_vault != address(dHEDGEStableYield), "Cant change to same vault");

        want.safeDecreaseAllowance(address(dHEDGEStableYield), type(uint256).max);

        setVault(_vault);
    }

    function setVault(address _vault) internal {
        //dHEDGEStableYield = IYakFarm(_vault);

        lastPPS = toWant(1000000);
        lastShares = balanceOfVault();
        want.safeApprove(_vault, type(uint256).max);
    }

    function toWant(uint256 _shares) public view returns (uint256) {
        //return YakFarm.getDepositTokensForShares(_shares);
        uint256 price = dHEDGEStableYield.tokenPrice();
        return price.mul(_shares);
    }

    function toWantPPS(uint256 _shares, uint256 _pps) public view returns (uint256) {
        return _pps.mul(_shares).div(1e6);
    }

    //takes underlying and converts it to Beef Vault share price for withdraw
    //@param _amount The amount in the underlying asset needed
    function toShares(uint256 _amount) internal view returns (uint256) {
        //return YakFarm.getSharesForDepositTokens(_amount);
        uint256 price = dHEDGEStableYield.tokenPrice();
        return _amount.div(price);
    }

    function balanceOfToken(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    //returns balance of unerlying asset
    function balanceOfVault() public view returns (uint256) {
        //check this works
        return balanceOfToken(address(dHEDGEStableYield));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return toWant(balanceOfVault()).add(balanceOfWant());
    }

    function getTokenOutPathV2(address _tokenIn, address _tokenOut) internal view returns (address[] memory _path) {
        bool isWeth = _tokenIn == weth || _tokenOut == weth;
        _path = new address[](isWeth ? 2 : 3);
        _path[0] = _tokenIn;

        if (isWeth) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = weth;
            _path[2] = _tokenOut;
        }
    }

    function investHarvest() internal {
        // send all of our usdc tokens to be deposited
        uint256 toInvest = balanceOfToken(address(usdc));
        // stake only if we have something to stake
        if (toInvest > 0) {
            dHEDGEStableYield.deposit(address(usdc), toInvest);
        }
    }

    //sell dHedge function
    function _disposeOfhedge() internal {
        uint256 _hedge = balanceOfToken(address(hedgeToken));
        if (_hedge < minhedgeToSell) {
            return;
        }

        router.swapExactTokensForTokens(_hedge, 0, getTokenOutPathV2(address(hedgeToken), usdc), address(this), now);
        investHarvest();
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
        // Harvest DHT tokens into want tokens
        _disposeOfhedge();

        uint256 shares = balanceOfVault();
        uint256 pps = toWant(1000000);
        uint256 prev;
        uint256 current;

        if (shares >= lastShares) {
            prev = toWantPPS(lastShares, lastPPS);
            current = toWant(lastShares);
        } else {
            prev = toWantPPS(shares, lastPPS);
            current = toWant(shares);
        }

        if (current > prev) {
            _profit = current.sub(prev);
        } else {
            _loss = prev.sub(current);
        }

        lastPPS = pps;
        lastShares = shares;
    }

    //invests available tokens
    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        investHarvest();
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        if (balanceOfWant() >= _amountNeeded) {
            return (_amountNeeded, 0);
        } else if (balanceOfToken(address(hedgeToken)) > 0) {
            _disposeOfhedge();
            if (balanceOfWant() >= _amountNeeded) {
                return (_amountNeeded, 0);
            }
        } else {
            uint256 wantBal = balanceOfWant();
            uint256 loss = _amountNeeded.sub(wantBal);
            return (wantBal, loss);
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        return balanceOfWant();
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        //dHEDGEStableYield.withdraw(balanceOfVault());
        return;
    }

    function protectedTokens() internal view override returns (address[] memory) {
        //address[] memory protected = new address[](1);
        //protected[0] = address(dHEDGEStableYield);
    }

    //WARNING. manipulatable and simple routing. Only use for safe functions
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

        uint256[] memory amounts = router.getAmountsOut(_amount, getTokenOutPathV2(start, end));

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
        uint256 price = dHEDGEStableYield.tokenPrice();
        uint256 _usdc = priceCheck(wmatic, usdc, _amtInWei);
        return _usdc.mul(price.div(10**(18 - 6)));
        //valueB = valueA / (10**(18-6))
    }
}
