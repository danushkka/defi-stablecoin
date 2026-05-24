// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintDscIsCalled;
    address[] public usersDepositedCollateral;
    mapping(address user => address collateral) public collateralDepositedByUser;

    uint96 public constant MAX_DEPOSIT_COLLATERAL = type(uint96).max;

    ////////////////////////////////////
    //////////// FUNCTIONS /////////////
    ////////////////////////////////////

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        engine = _dscEngine;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_COLLATERAL);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        for (uint256 i = 0; i < usersDepositedCollateral.length; i++) {
            if (usersDepositedCollateral[i] == msg.sender) {
                return;
            }
        }

        usersDepositedCollateral.push(msg.sender);
        collateralDepositedByUser[msg.sender] = address(collateral);
    }

    function mintDsc(uint256 amountToMint, uint256 senderSeed) public {
        if (usersDepositedCollateral.length == 0) {
            return;
        }
        address sender = usersDepositedCollateral[senderSeed % usersDepositedCollateral.length];

        (uint256 totalDscMinted, uint256 userCollateralValueInCny) = engine.getAccountInformation(sender);
        uint256 maxAmountToMint = (userCollateralValueInCny * 50) / 100;

        if (maxAmountToMint <= totalDscMinted) return;
        uint256 safeMax = maxAmountToMint - totalDscMinted;
        if (safeMax == 0) return;

        amountToMint = bound(amountToMint, 0, safeMax);
        if (amountToMint == 0) return;

        vm.startPrank(sender);
        engine.mintDsc(amountToMint);
        timesMintDscIsCalled++;
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateralToRedeem) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 userCollateralBalance = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateralToRedeem = bound(amountCollateralToRedeem, 0, userCollateralBalance);

        if (amountCollateralToRedeem == 0) return;

        (uint256 totalDscMinted,) = engine.getAccountInformation(msg.sender);
        if (totalDscMinted > 0) {
            uint256 remainingCollateralValue = engine.getAccountCollateralValueCny(msg.sender)
                - engine.getCnyValue(address(collateral), amountCollateralToRedeem);
            uint256 projectedHealthFactor = engine.calculateHealthFactor(totalDscMinted, remainingCollateralValue);
            if (projectedHealthFactor < engine.getMinHealthFactor()) return;
        }

        vm.startPrank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateralToRedeem);
        vm.stopPrank();
    }

    function burnDsc(uint256 amountToBurn) public {
        (uint256 totalDscMinted,) = engine.getAccountInformation(msg.sender);
        amountToBurn = bound(amountToBurn, 0, totalDscMinted);

        if (amountToBurn == 0) return;

        vm.startPrank(msg.sender);
        dsc.approve(address(engine), amountToBurn);
        engine.burnDsc(amountToBurn);
        vm.stopPrank();
    }

    ////////////////////////////////////
    ///////////// HELPERS //////////////
    ////////////////////////////////////

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    ////////////////////////////////////
    ///////////// GETTERS //////////////
    ////////////////////////////////////

    function getUsersDepositedCollateral() public view returns (address[] memory) {
        return usersDepositedCollateral;
    }
}
