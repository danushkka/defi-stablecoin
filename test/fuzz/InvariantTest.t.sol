// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    Handler handler;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        handler = new Handler(dsc, engine);
        targetContract(address(handler));
        (,,, weth, wbtc,) = config.activeNetworkConfig();
    }

    function invariant_protocolTotalSupplyMustBeLessThanCollateralValue() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 totalWethDepositedInCny = engine.getCnyValue(weth, totalWethDeposited);
        uint256 totalWbtcDepositedInCny = engine.getCnyValue(wbtc, totalWbtcDeposited);

        console2.log("Total Supply:", totalSupply);
        console2.log("Total WETH Deposited in CNY:", totalWethDepositedInCny);
        console2.log("Total WBTC Deposited in CNY:", totalWbtcDepositedInCny);
        console2.log("Times mintDsc is called:", handler.timesMintDscIsCalled());

        assert(totalSupply <= totalWethDepositedInCny + totalWbtcDepositedInCny);
    }

    function invariant_totalSupplyOfDscAndTotalCollateralValueMustMatchEngineRecords() public view {
        address[] memory users = handler.getUsersDepositedCollateral();
        uint256 totalDscMinted;
        uint256 totalWeth;
        uint256 totalWbtc;

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            (uint256 dscMintedByUser,) = engine.getAccountInformation(user);
            totalDscMinted += dscMintedByUser;

            uint256 wethDepositedByUser = engine.getCollateralBalanceOfUser(user, weth);
            uint256 wbtcDepositedByUser = engine.getCollateralBalanceOfUser(user, wbtc);

            totalWeth += wethDepositedByUser;
            totalWbtc += wbtcDepositedByUser;
        }

        assertEq(totalDscMinted, dsc.totalSupply());
        assertEq(totalWeth, IERC20(weth).balanceOf(address(engine)));
        assertEq(totalWbtc, IERC20(wbtc).balanceOf(address(engine)));
    }

    function invariant_healthFactorNeverBreaks() public view {
        address[] memory users = handler.getUsersDepositedCollateral();
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 dscMintedByUser,) = engine.getAccountInformation(users[i]);

            if (dscMintedByUser > 0) {
                uint256 userHealthFactor = engine.getHealthFactor(users[i]);
                assert(userHealthFactor >= engine.getMinHealthFactor());
            }
        }
    }

    function invariant_gettersShouldNotRevert() public view {
        engine.getAdditionalFeedPrecision();
        engine.getCollateralTokens();
        engine.getDecimalPrecision();
        engine.getDsc();
        engine.getLiquidationAdjustment();
        engine.getLiquidationBonus();
        engine.getLiquidationPrecision();
        engine.getMinHealthFactor();
    }
}
