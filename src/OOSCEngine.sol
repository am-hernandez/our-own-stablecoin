// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {OurOwnStablecoin} from "./OurOwnStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/*
 * @title OOSCEngine
 * @author A.M. Hernandez
 * @notice The system is designed to be as minimal as possible and have the tokens maintain a 1 token == $1 peg.
 * @notice This stablecoin has the following properties: Exogenous Collateral, Dollar-pegged, Algorithmically Stable.
 * @notice This stablecoin is like DAI without governance, fees, and only backed by WETH and WBTC.
 * @notice OOSC system should always be over collateralized. At no point should the value of all collateral be less than or equal to the value of all the OOSC.
 * @notice This contract is the core of the OOSC system. It handles all the logic for minting and redeeming OOSC, as well as depositing and withdrawing collateral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
 */
contract OOSCEngine is ReentrancyGuard {
    //
    // ERRORS
    //

    error OOSCEngine_MustBeMoreThanZero();
    error OOSCEngine_TokenAddressesAndPriceFeedAddressesLengthMismatch();
    error OOSCEngine_TokenNotAllowed();
    error OOSCEngine_TransferFailed();
    error OOSCEngine_BreaksHealthFactor(uint256 userHealthFactor);
    error OOSCEngine_InvalidPrice();
    error OOSCEngine_MintFailed();

    //
    // STATE VARIABLES
    //

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // must be at least 200% collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountOoscMinted) private s_ooscMinted;
    address[] private s_collateralTokens;

    OurOwnStablecoin private immutable I_OOSC;

    //
    // EVENTS
    //

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    //
    // MODIFIERS
    //

    modifier isAllowedToken(address token) {
        if (token == address(0)) {
            revert OOSCEngine_TokenNotAllowed();
        }
        _;
    }

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert OOSCEngine_MustBeMoreThanZero();
        }
        _;
    }

    //
    // FUNCTIONS
    //

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address ooscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert OOSCEngine_TokenAddressesAndPriceFeedAddressesLengthMismatch();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        I_OOSC = OurOwnStablecoin(ooscAddress);
    }

    //
    // EXTERNAL FUNCTIONS
    //

    function depositCollateralAndMintOosc() external {}

    /*
     * @param tokenCollateralAddress The address of the token collateral to
     * deposit
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert OOSCEngine_TransferFailed();
        }
    }

    function redeemCollateralForOosc() external {}

    function redeemCollateral() external {}

    /*
     * @param amountOoscToMint The amount of OOSC to mint
     * @notice The caller must have enough collateral deposited to mint the OOSC
     */
    function mintOosc(uint256 amountOoscToMint) external moreThanZero(amountOoscToMint) nonReentrant {
        s_ooscMinted[msg.sender] += amountOoscToMint;

        // if user attempts to mint more than the total collateral value, revert
        _revertIfHealthFactorBroken(msg.sender);

        bool minted = I_OOSC.mint(msg.sender, amountOoscToMint);
        if (!minted) {
            revert OOSCEngine_MintFailed();
        }
    }

    function burnOosc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    //
    // PRIVATE & INTERNAL FUNCTIONS
    //

    /*
     * @notice Returns the total OOSC minted and the collateral value in USD
     * @param user The address of the user to get the account information of
     * @return totalOoscMinted The total OOSC minted by the user
     * @return collateralValueInUsd The collateral value in USD
    */
    function getAccountInformation(address user)
        private
        view
        returns (uint256 totalOoscMinted, uint256 collateralValueInUsd)
    {
        totalOoscMinted = s_ooscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * @notice Returns how close to liquidation the user is
     * @notice If user goes below 1, they get liquidated
     * @param user The address of the user to check the health factor of
     * @return The health factor of the user
     */
    function _healthFactor(address user) internal view returns (uint256) {
        // total OOSC minted
        // total collateral VALUE

        (uint256 totalOoscMinted, uint256 collateralValueInUsd) = getAccountInformation(user);

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // ex. 1000 ETH / 100 OOSC
        // 1000 * 50 = 50000 / 100 = (500 / 100) > 1
        return (collateralAdjustedForThreshold * PRECISION) / totalOoscMinted;
    }

    /*
     * @notice Reverts if the user does not have enough collateral
     * @param user The address of the user to check the health factor of
     */
    function _revertIfHealthFactorBroken(address user) internal view {
        // Check health factor, does user have enough collateral?
        // Revert if the user does not have enough collateral
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert OOSCEngine_BreaksHealthFactor(userHealthFactor);
        }
    }

    //
    // PUBLIC FUNCTIONS
    //

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token,
        // get the amount the user deposited,
        // and map it to the price to get the USD value

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getTokenUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenUsdValue(address token, uint256 amount) public view returns (uint256) {
        // get the price feed of the token
        // get the price of the token
        // return the USD value

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // if (price <= 0) revert OOSCEngine_InvalidPrice();
        uint256 safePrice = SafeCast.toUint256(price);

        // ex. 1 ETH = $1000
        // The returned value from CL will be 1000 * 1e8 (8 decimals for ETH)
        return ((safePrice * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
