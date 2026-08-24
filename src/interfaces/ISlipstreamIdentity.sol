// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface ISlipstreamFactoryIdentity {
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address);
}

interface ISlipstreamPoolIdentity {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function tickSpacing() external view returns (int24);
}

interface ISlipstreamRouterIdentity {
    function factory() external view returns (address);
}
