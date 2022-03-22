//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;

interface IdHedgePool {
    function factory() external view returns (address);

    function poolManagerLogic() external view returns (address);

    function setPoolManagerLogic(address _poolManagerLogic) external returns (bool);

    function availableManagerFee() external view returns (uint256 fee);

    function tokenPrice() external view returns (uint256 price);

    function tokenPriceWithoutManagerFee() external view returns (uint256 price);

    function deposit(address _asset, uint256 _amount) external returns (uint256 liquidityMinted);

    function withdraw(uint256 _fundTokenAmount) external;

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}
